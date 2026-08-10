#!/usr/bin/env python3

import contextlib
import io
import os
import runpy
import sys
import types


SCRIPT = sys.argv[1]
USER_ID = 17
USERNAME = "oauth-fixture@example.invalid"
MATCHING_SESSION = "matching-session-secret"
OTHER_SESSION = "other-session-secret"
WEB_TOKEN = "web-token-secret"
SYNC_TOKEN = "sync-token-secret"
REPO_API_TOKEN = "repo-api-token-secret"


def module(name, **attributes):
    value = types.ModuleType(name)
    value.__dict__.update(attributes)
    sys.modules[name] = value
    return value


class UserRecord:
    def __init__(self, password="!"):
        self.id = USER_ID
        self.username = USERNAME
        self.email = USERNAME
        self.enc_password = password
        self.password = password
        self.is_active = True
        self.is_staff = True
        self.save_count = 0

    def save(self):
        self.save_count += 1
        return 0


class UserManager:
    def get(self, *, id):
        if id != USER_ID:
            raise KeyError(id)
        return state["user"]


class ExistsQuery:
    def __init__(self, exists):
        self._exists = exists

    def exists(self):
        return self._exists


class SocialAuthManager:
    def filter(self, *, username, provider):
        return ExistsQuery(
            state["oauth_linked"] and username == USERNAME and provider == "pocket-id"
        )


class SessionRecord:
    def __init__(self, session_key, username):
        self.session_key = session_key
        self._username = username

    def get_decoded(self):
        return {"_auth_user_name": self._username}


class DeleteQuery:
    def __init__(self, collection, predicate):
        self._collection = collection
        self._predicate = predicate

    def delete(self):
        self._collection[:] = [item for item in self._collection if not self._predicate(item)]


class SessionManager:
    def all(self):
        return list(state["sessions"])

    def filter(self, *, session_key__in):
        keys = set(session_key__in)
        return DeleteQuery(state["sessions"], lambda session: session.session_key in keys)


class AdminRoleManager:
    def filter(self, *, email):
        return DeleteQuery(state["admin_roles"], lambda role: role == email)


class Atomic:
    def __enter__(self):
        state["atomic_entries"] += 1
        state["atomic_depth"] += 1

    def __exit__(self, exc_type, exc_value, traceback):
        state["atomic_depth"] -= 1


class Transaction:
    @staticmethod
    def atomic():
        return Atomic()


class User:
    objects = UserManager()


class SocialAuthUser:
    objects = SocialAuthManager()


class Session:
    objects = SessionManager()


class AdminRole:
    objects = AdminRoleManager()


def clear_token(username):
    assert username == USERNAME
    state["clear_token_calls"].append(username)
    state["web_tokens"].clear()
    state["sync_tokens"].clear()


def inactive_user(username):
    assert state["atomic_depth"] == 1
    state["inactive_user_calls"].append(username)
    clear_token(username)
    state["repo_api_tokens"].clear()


module("django", __path__=[])
module("django.contrib", __path__=[])
module("django.contrib.sessions", __path__=[])
module("django.contrib.sessions.models", Session=Session)
module("django.db", transaction=Transaction)
module("seahub", __path__=[])
module("seahub.auth", __path__=[])
module("seahub.auth.models", SocialAuthUser=SocialAuthUser)
module("seahub.base", __path__=[])
module("seahub.base.accounts", User=User)
module("seahub.role_permissions", __path__=[])
module("seahub.role_permissions.models", AdminRole=AdminRole)
module("seahub.utils", clear_token=clear_token, inactive_user=inactive_user)


def reset(password="!", oauth_linked=True):
    global state
    state = {
        "user": UserRecord(password),
        "oauth_linked": oauth_linked,
        "sessions": [
            SessionRecord(MATCHING_SESSION, USERNAME),
            SessionRecord(OTHER_SESSION, "other-fixture@example.invalid"),
        ],
        "admin_roles": [USERNAME, "other-fixture@example.invalid"],
        "web_tokens": [WEB_TOKEN],
        "sync_tokens": [SYNC_TOKEN],
        "repo_api_tokens": [REPO_API_TOKEN],
        "clear_token_calls": [],
        "inactive_user_calls": [],
        "atomic_entries": 0,
        "atomic_depth": 0,
    }


def run_script():
    os.environ["SEAFILE_ADMIN_USER_ID"] = str(USER_ID)
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        runpy.run_path(SCRIPT, run_name="__main__")
    return output.getvalue()


reset(password="stored-native-hash", oauth_linked=False)
try:
    run_script()
except RuntimeError as error:
    assert str(error) == "Refusing to disable the native break-glass administrator"
else:
    raise AssertionError("native break-glass administrator was not refused")
assert state["atomic_entries"] == 0
assert state["user"].save_count == 0
assert state["repo_api_tokens"] == [REPO_API_TOKEN]

reset()
output = run_script()
assert output == "OAuth administrator authority, sessions, and tokens revoked; account disabled\n"
assert state["atomic_entries"] == 1
assert state["atomic_depth"] == 0
assert state["inactive_user_calls"] == [USERNAME]
assert state["repo_api_tokens"] == []
assert state["web_tokens"] == []
assert state["sync_tokens"] == []
assert [session.session_key for session in state["sessions"]] == [OTHER_SESSION]
assert state["admin_roles"] == ["other-fixture@example.invalid"]
assert state["user"].is_active is False
assert state["user"].is_staff is False
assert state["user"].enc_password == "!"
assert state["user"].password == "!"
assert state["user"].save_count == 1
for secret in (MATCHING_SESSION, WEB_TOKEN, SYNC_TOKEN, REPO_API_TOKEN):
    assert secret not in output
