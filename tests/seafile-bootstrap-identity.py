#!/usr/bin/env python3
"""Execute Seafile's generated bootstrap identity status helper against a fake API."""

from __future__ import annotations

import argparse
import contextlib
import io
import runpy
import sys
import types
import unittest
from dataclasses import dataclass
from unittest.mock import patch


@dataclass
class FakeUser:
    email: str
    password: str
    is_active: bool = True
    is_staff: bool = False


@dataclass(frozen=True)
class FakeSocialAuthUser:
    username: str
    provider: str = "pocket-id"


class FakeQuerySet:
    def __init__(self, values: list[FakeSocialAuthUser]) -> None:
        self.values = values

    def values_list(self, field: str, *, flat: bool) -> list[str]:
        if field != "username" or not flat:
            raise AssertionError("unexpected SocialAuthUser values_list query")
        return [getattr(value, field) for value in self.values]


class FakeManager:
    def __init__(self, values: list[FakeSocialAuthUser]) -> None:
        self.values = values

    def filter(self, **criteria: object) -> FakeQuerySet:
        return FakeQuerySet(
            [
                value
                for value in self.values
                if all(getattr(value, field) == expected for field, expected in criteria.items())
            ]
        )


class SeafileFixture:
    def __init__(self, oauth_count: int) -> None:
        native = FakeUser("native@example.test", "native-password-hash", is_staff=True)
        oauth_users = [
            FakeUser(f"oauth-{index}@example.test", "!") for index in range(1, oauth_count + 1)
        ]
        self.users = [native, *oauth_users]
        self.social_auth_users = [FakeSocialAuthUser(user.email) for user in oauth_users]

    def modules(self) -> dict[str, types.ModuleType]:
        seaserv = types.ModuleType("seaserv")
        seaserv.ccnet_api = types.SimpleNamespace(
            get_emailusers=lambda source, start, limit: list(self.users)
        )

        seahub = self._package("seahub")
        seahub_auth = self._package("seahub.auth")
        seahub_auth_models = types.ModuleType("seahub.auth.models")
        seahub_auth_models.SocialAuthUser = types.SimpleNamespace(
            objects=FakeManager(self.social_auth_users)
        )

        return {
            "seaserv": seaserv,
            "seahub": seahub,
            "seahub.auth": seahub_auth,
            "seahub.auth.models": seahub_auth_models,
        }

    @staticmethod
    def _package(name: str) -> types.ModuleType:
        package = types.ModuleType(name)
        package.__path__ = []
        return package

    def run(self, script: str) -> str:
        with patch.dict(sys.modules, self.modules()):
            with contextlib.redirect_stdout(io.StringIO()) as stdout:
                runpy.run_path(script, run_name="__main__")
        return stdout.getvalue()


class BootstrapIdentityStatusTest(unittest.TestCase):
    status_script: str

    def assert_boundary_rejected(self, fixture: SeafileFixture) -> None:
        with self.assertRaisesRegex(SystemExit, "identity boundary"):
            fixture.run(self.status_script)

    def test_one_or_two_oauth_users_are_accepted(self) -> None:
        for oauth_count in (1, 2):
            with self.subTest(oauth_count=oauth_count):
                fixture = SeafileFixture(oauth_count)

                self.assertEqual(
                    fixture.run(self.status_script),
                    f"active={oauth_count + 1}\t"
                    f"native_break_glass_admins=1\toauth={oauth_count}\tlimit=3\n",
                )

    def test_native_only_boundary_is_rejected(self) -> None:
        self.assert_boundary_rejected(SeafileFixture(0))

    def test_three_oauth_users_are_rejected(self) -> None:
        self.assert_boundary_rejected(SeafileFixture(3))

    def test_password_capable_oauth_user_is_rejected(self) -> None:
        fixture = SeafileFixture(1)
        fixture.users[1].password = "unexpected-oauth-password-hash"

        self.assert_boundary_rejected(fixture)

    def test_multiple_native_administrators_are_rejected(self) -> None:
        fixture = SeafileFixture(1)
        fixture.users.append(FakeUser("second-native@example.test", "password-hash", is_staff=True))

        self.assert_boundary_rejected(fixture)

    def test_unclassified_active_user_is_rejected(self) -> None:
        fixture = SeafileFixture(1)
        fixture.users.append(FakeUser("unclassified@example.test", "!"))

        self.assert_boundary_rejected(fixture)

    def test_more_than_three_active_users_are_rejected(self) -> None:
        fixture = SeafileFixture(2)
        fixture.users.append(FakeUser("fourth@example.test", "!"))

        self.assert_boundary_rejected(fixture)

    def test_native_administrator_must_be_active_and_staff(self) -> None:
        for attribute in ("is_active", "is_staff"):
            with self.subTest(attribute=attribute):
                fixture = SeafileFixture(1)
                setattr(fixture.users[0], attribute, False)

                self.assert_boundary_rejected(fixture)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    BootstrapIdentityStatusTest.status_script = arguments.status
    unittest.main(argv=[sys.argv[0]], verbosity=2)
