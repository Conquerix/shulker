#!/usr/bin/env python3
"""Execute Seafile's generated restore identity helpers against a fake API."""

from __future__ import annotations

import argparse
import contextlib
import io
import os
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
    username: str | None = None

    def __post_init__(self) -> None:
        if self.username is None:
            self.username = self.email
        self.enc_password = self.password
        self._plain_password = None
        self.save_calls = 0

    def set_password(self, password: str) -> None:
        self._plain_password = password
        self.password = f"encoded:{password}"
        self.enc_password = self.password

    def save(self) -> int:
        self.save_calls += 1
        return 0

    def check_password(self, password: str) -> bool:
        return self._plain_password == password


@dataclass(frozen=True)
class FakeSocialAuthUser:
    username: str
    provider: str = "pocket-id"


class FakeQuerySet:
    def __init__(self, values: list[object]) -> None:
        self.values = values

    def values_list(self, field: str, *, flat: bool) -> list[object]:
        if field != "username" or not flat:
            raise AssertionError("unexpected SocialAuthUser values_list query")
        return [getattr(value, field) for value in self.values]

    def exists(self) -> bool:
        return bool(self.values)


class FakeManager:
    def __init__(self, values: list[object]) -> None:
        self.values = values

    def filter(self, **criteria: object) -> FakeQuerySet:
        return FakeQuerySet(
            [
                value
                for value in self.values
                if all(getattr(value, field) == expected for field, expected in criteria.items())
            ]
        )


class FakeUserManager:
    def __init__(self, users: list[FakeUser]) -> None:
        self.users = users

    def get(self, *, email: str) -> FakeUser:
        matches = [user for user in self.users if user.email == email]
        if len(matches) != 1:
            raise LookupError(f"expected one user for {email}, found {len(matches)}")
        return matches[0]


class SeafileFixture:
    def __init__(self, users: list[FakeUser], oauth_usernames: list[str]) -> None:
        self.users = users
        self.social_auth_users = [FakeSocialAuthUser(username) for username in oauth_usernames]

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
        seahub_base = self._package("seahub.base")
        seahub_base_accounts = types.ModuleType("seahub.base.accounts")
        seahub_base_accounts.User = types.SimpleNamespace(objects=FakeUserManager(self.users))

        return {
            "seaserv": seaserv,
            "seahub": seahub,
            "seahub.auth": seahub_auth,
            "seahub.auth.models": seahub_auth_models,
            "seahub.base": seahub_base,
            "seahub.base.accounts": seahub_base_accounts,
        }

    @staticmethod
    def _package(name: str) -> types.ModuleType:
        package = types.ModuleType(name)
        package.__path__ = []
        return package

    def run(self, script: str, **environment: str) -> str:
        with patch.dict(sys.modules, self.modules()):
            with patch.dict(os.environ, environment, clear=False):
                with contextlib.redirect_stdout(io.StringIO()) as stdout:
                    runpy.run_path(script, run_name="__main__")
        return stdout.getvalue()


def valid_fixture(
    native_email: str = "native@example.test", oauth_count: int = 2
) -> tuple[SeafileFixture, FakeUser]:
    native = FakeUser(native_email, "existing-password-hash", is_staff=True)
    oauth_users = [
        FakeUser(f"oauth-{index}@example.test", "!") for index in range(1, oauth_count + 1)
    ]
    fixture = SeafileFixture([native, *oauth_users], [user.email for user in oauth_users])
    return fixture, native


class RestoreIdentityHelpersTest(unittest.TestCase):
    identify_script: str
    reset_script: str
    verify_script: str

    def assert_boundary_rejected(self, fixture: SeafileFixture, native: FakeUser) -> None:
        with self.assertRaisesRegex(RuntimeError, "identity boundary is not safe"):
            fixture.run(self.identify_script)

        native.set_password("restore-only-secret")
        with self.assertRaisesRegex(RuntimeError, "identity boundary"):
            fixture.run(
                self.verify_script,
                RESTORE_NATIVE_EMAIL=native.email,
                RESTORE_PASSWORD="restore-only-secret",
            )

    def test_one_or_two_oauth_boundaries_reset_native_admin_in_place(self) -> None:
        for oauth_count in (1, 2):
            with self.subTest(oauth_count=oauth_count):
                fixture, native = valid_fixture(oauth_count=oauth_count)

                self.assertEqual(fixture.run(self.identify_script), f"{native.email}\n")
                before_identity = id(native)
                before_user_count = len(fixture.users)
                fixture.run(
                    self.reset_script,
                    RESTORE_NATIVE_EMAIL=native.email,
                    RESTORE_PASSWORD="restore-only-secret",
                )

                self.assertEqual(id(native), before_identity)
                self.assertEqual(len(fixture.users), before_user_count)
                self.assertEqual(native.save_calls, 1)
                self.assertTrue(native.check_password("restore-only-secret"))
                fixture.run(
                    self.verify_script,
                    RESTORE_NATIVE_EMAIL=native.email,
                    RESTORE_PASSWORD="restore-only-secret",
                )
                with self.assertRaisesRegex(RuntimeError, "credential verification failed"):
                    fixture.run(
                        self.verify_script,
                        RESTORE_NATIVE_EMAIL=native.email,
                        RESTORE_PASSWORD="wrong-secret",
                    )

    def test_native_only_boundary_is_rejected(self) -> None:
        fixture, native = valid_fixture(oauth_count=0)

        self.assert_boundary_rejected(fixture, native)

    def test_dummy_restore_admin_is_rejected(self) -> None:
        fixture, _native = valid_fixture("restore-admin@restore.invalid")

        self.assert_boundary_rejected(fixture, _native)

    def test_three_oauth_users_are_rejected(self) -> None:
        fixture, native = valid_fixture(oauth_count=3)

        self.assert_boundary_rejected(fixture, native)

    def test_more_than_three_active_users_are_rejected(self) -> None:
        fixture, native = valid_fixture()
        fixture.users.append(FakeUser("unexpected@example.test", "!"))

        self.assert_boundary_rejected(fixture, native)

    def test_password_capable_oauth_user_is_rejected_without_mutation(self) -> None:
        fixture, native = valid_fixture()
        oauth_user = fixture.users[1]
        oauth_user.password = "unexpected-oauth-password-hash"
        oauth_user.enc_password = oauth_user.password
        oauth_user.is_staff = True

        self.assert_boundary_rejected(fixture, native)
        with self.assertRaisesRegex(RuntimeError, "OAuth-linked"):
            fixture.run(
                self.reset_script,
                RESTORE_NATIVE_EMAIL=oauth_user.email,
                RESTORE_PASSWORD="restore-only-secret",
            )
        self.assertEqual(oauth_user.password, "unexpected-oauth-password-hash")
        self.assertEqual(oauth_user.save_calls, 0)

    def test_multiple_native_administrators_are_rejected(self) -> None:
        fixture, native = valid_fixture(oauth_count=1)
        fixture.users.append(FakeUser("second-native@example.test", "password-hash", is_staff=True))

        self.assert_boundary_rejected(fixture, native)

    def test_unclassified_active_user_is_rejected(self) -> None:
        fixture, native = valid_fixture(oauth_count=1)
        fixture.users.append(FakeUser("unclassified@example.test", "!"))

        self.assert_boundary_rejected(fixture, native)

    def test_native_administrator_must_be_active_and_staff(self) -> None:
        for attribute in ("is_active", "is_staff"):
            with self.subTest(attribute=attribute):
                fixture, native = valid_fixture(oauth_count=1)
                setattr(native, attribute, False)

                self.assert_boundary_rejected(fixture, native)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--identify", required=True)
    parser.add_argument("--reset", required=True)
    parser.add_argument("--verify", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    RestoreIdentityHelpersTest.identify_script = arguments.identify
    RestoreIdentityHelpersTest.reset_script = arguments.reset
    RestoreIdentityHelpersTest.verify_script = arguments.verify
    unittest.main(argv=[sys.argv[0]], verbosity=2)
