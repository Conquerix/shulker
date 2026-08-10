{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.seafile;
  environmentFile = "/run/seafile-host/environment";
  maintenanceLock = "/run/lock/seafile-maintenance.lock";
  pythonCommand = "/opt/seafile/seafile-server-latest/seahub.sh python-env python -";
  listUsersPython = ''
    from seaserv import ccnet_api
    from seahub.auth.models import SocialAuthUser

    users = sorted(ccnet_api.get_emailusers("DB", -1, -1), key=lambda user: user.id)
    oauth_usernames = set(
        SocialAuthUser.objects.filter(provider="pocket-id").values_list("username", flat=True)
    )
    for user in users:
        print(
            f"id={user.id}\tactive={bool(user.is_active)}\tadmin={bool(user.is_staff)}"
            f"\tpassword={'passwordless' if user.password == '!' else 'capable'}"
            f"\toauth={'linked' if user.email in oauth_usernames else 'unlinked'}"
        )
  '';
  licenseStatusPython = ''
    from seaserv import ccnet_api
    from seahub.auth.models import SocialAuthUser

    license_user_limit = ${toString cfg.licenseUserLimit}
    users = ccnet_api.get_emailusers("DB", -1, -1)
    active_users = [user for user in users if user.is_active]
    active_user_count = len(active_users)
    oauth_usernames = set(
        SocialAuthUser.objects.filter(provider="pocket-id").values_list("username", flat=True)
    )
    oauth_count = sum(user.email in oauth_usernames for user in active_users)
    native_count = sum(
        user.email not in oauth_usernames and user.password != "!" for user in active_users
    )
    unclassified_count = active_user_count - oauth_count - native_count
    print(
        f"active={active_user_count}\tlimit={license_user_limit}"
        f"\tnative_break_glass={native_count}\toauth={oauth_count}"
        f"\tunclassified={unclassified_count}"
    )
    if active_user_count > license_user_limit:
        raise SystemExit("Seafile active named-user count exceeds the licensed limit")
  '';
  promoteAdminPython = ''
    import os

    from django.db import transaction
    from seahub.auth.models import SocialAuthUser
    from seahub.base.accounts import User

    user_id = int(os.environ["SEAFILE_ADMIN_USER_ID"])
    user = User.objects.get(id=user_id)
    linked = SocialAuthUser.objects.filter(
        username=user.username,
        provider="pocket-id",
    ).exists()
    if not user.is_active or not linked or user.enc_password != "!":
        raise RuntimeError("Refusing to promote a non-active or password-capable account")

    with transaction.atomic():
        user.password = user.enc_password
        user.is_staff = True
        if user.save() != 0:
            raise RuntimeError("Seafile refused the administrator update")

    refreshed = User.objects.get(id=user_id)
    if not refreshed.is_staff or refreshed.enc_password != "!":
        raise RuntimeError("Administrator promotion did not preserve passwordless OAuth state")
    print("OAuth administrator authority is present; passwordless state preserved")
  '';
  revokeAdminPython = ''
    import os

    from django.contrib.sessions.models import Session
    from django.db import transaction
    from seahub.auth.models import SocialAuthUser
    from seahub.base.accounts import User
    from seahub.role_permissions.models import AdminRole
    from seahub.utils import inactive_user

    user_id = int(os.environ["SEAFILE_ADMIN_USER_ID"])
    user = User.objects.get(id=user_id)
    linked = SocialAuthUser.objects.filter(
        username=user.username,
        provider="pocket-id",
    ).exists()
    if not linked or user.enc_password != "!":
        raise RuntimeError("Refusing to disable the native break-glass administrator")

    session_keys = []
    for session in Session.objects.all():
        try:
            if session.get_decoded().get("_auth_user_name") == user.username:
                session_keys.append(session.session_key)
        except Exception:
            continue

    with transaction.atomic():
        Session.objects.filter(session_key__in=session_keys).delete()
        AdminRole.objects.filter(email=user.username).delete()
        inactive_user(user.username)
        user.password = user.enc_password
        user.is_staff = False
        user.is_active = False
        if user.save() != 0:
            raise RuntimeError("Seafile refused the account disable")

    print("OAuth administrator authority, sessions, and tokens revoked; account disabled")
  '';
  bootstrapStatusPython = ''
    from seaserv import ccnet_api
    from seahub.auth.models import SocialAuthUser

    license_user_limit = ${toString cfg.licenseUserLimit}
    active_users = [user for user in ccnet_api.get_emailusers("DB", -1, -1) if user.is_active]
    active_user_count = len(active_users)
    oauth_usernames = set(
        SocialAuthUser.objects.filter(provider="pocket-id").values_list("username", flat=True)
    )
    oauth_users = [user for user in active_users if user.email in oauth_usernames]
    native_admins = [
        user
        for user in active_users
        if user.email not in oauth_usernames and user.password != "!" and user.is_staff
    ]
    recognized = len(oauth_users) + len(native_admins)
    valid = (
        active_user_count <= license_user_limit
        and len(native_admins) == 1
        and len(oauth_users) <= 2
        and all(user.password == "!" for user in oauth_users)
        and recognized == active_user_count
    )
    print(
        f"active={active_user_count}\tnative_break_glass_admins={len(native_admins)}"
        f"\toauth={len(oauth_users)}\tlimit={license_user_limit}"
    )
    if not valid:
        raise SystemExit("Seafile identity boundary is not in the approved bootstrap state")
  '';
  verifyStoredRecoveryPython = ''
    import os

    from seahub.auth.models import SocialAuthUser
    from seahub.base.accounts import User

    native_email = os.environ["INIT_SEAFILE_ADMIN_EMAIL"]
    native_password = os.environ["INIT_SEAFILE_ADMIN_PASSWORD"]
    user = User.objects.get(email=native_email)
    if not user.is_active or not user.is_staff or user.enc_password == "!":
        raise RuntimeError("Stored native administrator lacks recovery authority")
    if SocialAuthUser.objects.filter(username=user.username, provider="pocket-id").exists():
        raise RuntimeError("Stored native administrator collides with an OAuth identity")
    if not user.check_password(native_password):
        raise RuntimeError("Stored native administrator credential did not survive restart")
    print("Stored native administrator recovery verified after restart")
  '';
  commonShell = ''
    if [ "$(id -u)" -ne 0 ]; then
      echo "This Seafile administration command must run as root" >&2
      exit 77
    fi

    exec 9>${maintenanceLock}
    flock 9

    if ! systemctl is-active --quiet seafile-compose.service; then
      echo "Seafile Compose service is not active" >&2
      exit 69
    fi

    validate_seafile_container() {
      container_name="$(docker inspect --format '{{.Name}}' seafile)"
      project_name="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' seafile)"
      service_name="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' seafile)"
      running="$(docker inspect --format '{{.State.Running}}' seafile)"
      if [ "$container_name" != /seafile ] \
        || [ "$project_name" != seafile ] \
        || [ "$service_name" != seafile ] \
        || [ "$running" != true ]; then
        echo "Refusing to use an unexpected Seafile container" >&2
        exit 69
      fi
    }
    validate_seafile_container
  '';
  managementRuntimeInputs = [
    config.virtualisation.docker.package
    pkgs.coreutils
    pkgs.systemd
    pkgs.util-linux
  ];
  listUsersScript = pkgs.writeText "seafile-list-users.py" listUsersPython;
  licenseStatusScript = pkgs.writeText "seafile-license-status.py" licenseStatusPython;
  promoteAdminScript = pkgs.writeText "seafile-promote-oauth-admin.py" promoteAdminPython;
  revokeAdminScript = pkgs.writeText "seafile-revoke-oauth-admin.py" revokeAdminPython;
  bootstrapStatusScript = pkgs.writeText "seafile-bootstrap-status.py" bootstrapStatusPython;
  verifyStoredRecoveryScript = pkgs.writeText "seafile-verify-stored-recovery.py" verifyStoredRecoveryPython;
  runPython = script: ''
    docker exec -i seafile ${pythonCommand} <${script}
  '';
  listUsers = pkgs.writeShellApplication {
    name = "seafile-list-users";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      ${commonShell}
      ${runPython listUsersScript}
    '';
  };
  licenseStatus = pkgs.writeShellApplication {
    name = "seafile-license-status";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      ${commonShell}
      ${runPython licenseStatusScript}
    '';
  };
  promoteAdmin = pkgs.writeShellApplication {
    name = "seafile-promote-oauth-admin";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      if [ "$#" -ne 1 ] || [[ ! "$1" =~ ^[0-9]+$ ]]; then
        echo "Usage: seafile-promote-oauth-admin USER_ID" >&2
        exit 64
      fi
      export SEAFILE_ADMIN_USER_ID="$1"
      ${commonShell}
      docker exec -i --env SEAFILE_ADMIN_USER_ID seafile \
        ${pythonCommand} <${promoteAdminScript}
    '';
  };
  revokeAdmin = pkgs.writeShellApplication {
    name = "seafile-revoke-oauth-admin";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      if [ "$#" -ne 2 ] || [ "$1" != --disable-user ] || [[ ! "$2" =~ ^[0-9]+$ ]]; then
        echo "Usage: seafile-revoke-oauth-admin --disable-user USER_ID" >&2
        exit 64
      fi
      export SEAFILE_ADMIN_USER_ID="$2"
      ${commonShell}
      docker exec -i --env SEAFILE_ADMIN_USER_ID seafile \
        ${pythonCommand} <${revokeAdminScript}
    '';
  };
  bootstrapStatus = pkgs.writeShellApplication {
    name = "seafile-bootstrap-status";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      ${commonShell}
      ${runPython bootstrapStatusScript}
    '';
  };
  resetNativeAdminRunnerText = ''
    if [ "$#" -ne 1 ] || [ "$1" != --restore-stored ]; then
      echo "Usage: seafile-reset-native-admin --restore-stored" >&2
      echo "Ad hoc passwords are refused; rotate 1Password first under separate approval" >&2
      exit 64
    fi
    ${commonShell}
    if [ -z "''${INIT_SEAFILE_ADMIN_EMAIL:-}" ] \
      || [ -z "''${INIT_SEAFILE_ADMIN_PASSWORD:-}" ]; then
      echo "Stored native administrator credential is unavailable" >&2
      exit 65
    fi

    echo "WARNING: this performs a live Seafile credential mutation and full container restart" >&2
    read -r -p "Type RESTORE STORED to continue: " confirmation
    if [ "$confirmation" != "RESTORE STORED" ]; then
      echo "Stored native administrator recovery cancelled" >&2
      exit 1
    fi

    if ! printf '%s\n%s\n%s\n' \
      "$INIT_SEAFILE_ADMIN_EMAIL" \
      "$INIT_SEAFILE_ADMIN_PASSWORD" \
      "$INIT_SEAFILE_ADMIN_PASSWORD" \
      | docker exec -i seafile \
        /opt/seafile/seafile-server-latest/reset-admin.sh >/dev/null 2>&1; then
      echo "Stored native administrator reset failed" >&2
      exit 70
    fi

    docker restart seafile >/dev/null
    deadline="$(( $(date +%s) + 300 ))"
    while true; do
      running="$(docker inspect --format '{{.State.Running}}' seafile 2>/dev/null || true)"
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' seafile 2>/dev/null || true)"
      [ "$running" != true ] || [ "$health" != healthy ] || break
      [ "$(date +%s)" -lt "$deadline" ] || {
        echo "Seafile did not become healthy after stored credential recovery" >&2
        exit 70
      }
      sleep 2
    done
    validate_seafile_container
    export INIT_SEAFILE_ADMIN_EMAIL INIT_SEAFILE_ADMIN_PASSWORD
    docker exec -i \
      --env INIT_SEAFILE_ADMIN_EMAIL \
      --env INIT_SEAFILE_ADMIN_PASSWORD \
      seafile ${pythonCommand} <${verifyStoredRecoveryScript}
  '';
  resetNativeAdminRunner = pkgs.writeShellApplication {
    name = "seafile-reset-native-admin-runner";
    runtimeInputs = managementRuntimeInputs;
    text = resetNativeAdminRunnerText;
  };
  resetNativeAdmin = pkgs.writeShellApplication {
    name = "seafile-reset-native-admin";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "This Seafile administration command must run as root" >&2
        exit 77
      fi
      exec systemd-run \
        --collect \
        --pipe \
        --quiet \
        --wait \
        --property=EnvironmentFile=${lib.escapeShellArg environmentFile} \
        ${resetNativeAdminRunner}/bin/seafile-reset-native-admin-runner "$@"
    '';
  };
  bootstrapContractText = lib.concatStringsSep "\n" [
    listUsersPython
    licenseStatusPython
    promoteAdminPython
    revokeAdminPython
    bootstrapStatusPython
    verifyStoredRecoveryPython
    commonShell
    resetNativeAdminRunnerText
  ];
in
{
  options.shulker.system.modules.seafile.bootstrapContractText = lib.mkOption {
    type = lib.types.lines;
    readOnly = true;
    internal = true;
    description = "Seafile bootstrap and recovery source exposed for evaluation contracts.";
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.seafile.bootstrapContractText = bootstrapContractText;

    environment.systemPackages = [
      listUsers
      licenseStatus
      promoteAdmin
      revokeAdmin
      resetNativeAdmin
      bootstrapStatus
    ];
  };
}
