{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.paperless;
  environmentFile = config.services.onepassword-secrets.secrets.paperlessEnv.path;
  maintenanceLock = "/run/lock/paperless-maintenance.lock";
  groupsPython = ''
    from django.contrib.auth.models import Group, Permission
    from django.db import transaction

    user_permission_names = {
        "documents.add_document",
        "documents.view_correspondent",
        "documents.view_customfield",
        "documents.view_documenttype",
        "documents.view_note",
        "documents.add_note",
        "documents.change_note",
        "documents.delete_note",
        "documents.view_paperlesstask",
        "documents.change_paperlesstask",
        "documents.view_savedview",
        "documents.view_storagepath",
        "documents.view_tag",
    }

    def resolve_permissions(names):
        resolved = {}
        for permission in Permission.objects.select_related("content_type"):
            key = f"{permission.content_type.app_label}.{permission.codename}"
            if key in names:
                resolved[key] = permission
        missing = names - resolved.keys()
        if missing:
            raise RuntimeError(f"Missing Paperless permissions: {', '.join(sorted(missing))}")
        return list(resolved.values())

    user_permissions = resolve_permissions(user_permission_names)
    admin_permissions = list(
        Permission.objects.exclude(codename__icontains="sharelink")
    )

    with transaction.atomic():
        users, _ = Group.objects.get_or_create(name="paperless_users")
        family, _ = Group.objects.get_or_create(name="paperless_family")
        admins, _ = Group.objects.get_or_create(name="paperless_admins")
        users.permissions.set(user_permissions)
        family.permissions.clear()
        admins.permissions.set(admin_permissions)

    print(f"paperless_users: {len(user_permissions)} global permissions")
    print("paperless_family: 0 global permissions; object permissions only")
    print(f"paperless_admins: {len(admin_permissions)} permissions; share links excluded")
  '';
  listUsersPython = ''
    from django.contrib.auth import get_user_model

    for user in get_user_model().objects.prefetch_related("groups").order_by("username"):
        groups = ",".join(sorted(group.name for group in user.groups.all())) or "-"
        print(
            f"{user.username}\t{user.email}\tactive={user.is_active}"
            f"\tstaff={user.is_staff}\tsuperuser={user.is_superuser}"
            f"\tusable_password={user.has_usable_password()}\tgroups={groups}"
        )
  '';
  promoteAdminPython = ''
    import os
    from django.contrib.auth import get_user_model
    from django.contrib.auth.models import Group
    from django.db import transaction

    username = os.environ["PAPERLESS_BOOTSTRAP_USERNAME"]
    user = get_user_model().objects.get(username=username)
    if user.has_usable_password():
        raise RuntimeError("Refusing to promote a password-capable Paperless user")

    with transaction.atomic():
        admins = Group.objects.get(name="paperless_admins")
        user.groups.add(admins)
        user.is_staff = True
        user.is_superuser = True
        user.save(update_fields=["is_staff", "is_superuser"])

    print(f"Promoted OIDC user {username} without assigning a password")
  '';
  revokeAdminPython = ''
    import os
    from django.contrib.auth import get_user_model
    from django.contrib.auth.models import Group
    from django.contrib.sessions.models import Session
    from django.db import transaction
    from rest_framework.authtoken.models import Token

    username = os.environ["PAPERLESS_BOOTSTRAP_USERNAME"]
    user = get_user_model().objects.get(username=username)

    session_ids = []
    for session in Session.objects.all():
        if str(session.get_decoded().get("_auth_user_id")) == str(user.pk):
            session_ids.append(session.pk)

    with transaction.atomic():
        deleted_sessions, _ = Session.objects.filter(pk__in=session_ids).delete()
        deleted_tokens, _ = Token.objects.filter(user=user).delete()
        try:
            admins = Group.objects.get(name="paperless_admins")
        except Group.DoesNotExist:
            admins = None
        if admins is not None:
            user.groups.remove(admins)
        user.is_staff = False
        user.is_superuser = False
        user.is_active = False
        user.save(update_fields=["is_staff", "is_superuser", "is_active"])

    print(
        f"Revoked administrator {username}: sessions={deleted_sessions}, "
        f"tokens={deleted_tokens}, disabled=True"
    )
  '';
  enableUserPython = ''
    import os
    from django.contrib.auth import get_user_model
    from django.contrib.auth.models import Group
    from django.db import transaction

    username = os.environ["PAPERLESS_BOOTSTRAP_USERNAME"]
    user = get_user_model().objects.get(username=username)
    if user.has_usable_password():
        raise RuntimeError("Refusing to enable a password-capable Paperless user")

    try:
        admins = Group.objects.get(name="paperless_admins")
    except Group.DoesNotExist:
        admins = None
    if user.is_staff or user.is_superuser or (
        admins is not None and user.groups.filter(pk=admins.pk).exists()
    ):
        raise RuntimeError("Refusing to enable a user with remaining administrator authority")

    with transaction.atomic():
        user.is_active = True
        user.save(update_fields=["is_active"])

    print(f"Enabled non-administrator Paperless user {username}")
  '';
  fastmailPython = ''
    import json
    import os
    from django.contrib.auth import get_user_model
    from django.db import transaction
    from documents.models import Tag
    from paperless_mail.models import MailAccount, MailRule

    admin_username = os.environ["PAPERLESS_BOOTSTRAP_ADMIN_USERNAME"]
    routes = json.loads(os.environ["PAPERLESS_BOOTSTRAP_ROUTES_JSON"])
    username = os.environ["PAPERLESS_FASTMAIL_USERNAME"]
    password = os.environ["PAPERLESS_FASTMAIL_APP_PASSWORD"]
    users = get_user_model()
    admin = users.objects.get(username=admin_username)
    if admin.has_usable_password():
        raise RuntimeError("Fastmail administrator must be an OIDC-only user")

    desired_rule_ids = []
    managed_prefix = "Shulker route - "
    with transaction.atomic():
        account, _ = MailAccount.objects.update_or_create(
            name="Fastmail Paperless",
            defaults={
                "imap_server": "imap.fastmail.com",
                "imap_port": 993,
                "imap_security": MailAccount.ImapSecurity.SSL,
                "username": username,
                "password": password,
                "is_token": False,
                "character_set": "UTF-8",
                "account_type": MailAccount.MailAccountType.IMAP,
                "owner": admin,
            },
        )
        source_tag, _ = Tag.objects.get_or_create(
            name="Source: Fastmail",
            owner=None,
        )

        for order, route in enumerate(routes):
            owner = users.objects.get(username=route["owner"])
            if owner.has_usable_password():
                raise RuntimeError(f"Route owner {owner.username} is not OIDC-only")
            rule, _ = MailRule.objects.update_or_create(
                name=f"{managed_prefix}{route['name']}",
                owner=owner,
                defaults={
                    "order": order,
                    "account": account,
                    "enabled": True,
                    "folder": "INBOX",
                    "filter_to": route["address"],
                    "maximum_age": 30,
                    "attachment_type": MailRule.AttachmentProcessing.ATTACHMENTS_ONLY,
                    "consumption_scope": MailRule.ConsumptionScope.ATTACHMENTS_ONLY,
                    "action": MailRule.MailAction.MOVE,
                    "action_parameter": "Paperless/Processed",
                    "assign_title_from": MailRule.TitleSource.FROM_SUBJECT,
                    "assign_owner_from_rule": True,
                    "stop_processing": True,
                },
            )
            rule.assign_tags.set([source_tag])
            desired_rule_ids.append(rule.pk)

        removed, _ = MailRule.objects.filter(
            name__startswith=managed_prefix,
        ).exclude(pk__in=desired_rule_ids).delete()

    print(
        f"Fastmail Paperless configured: routes={len(desired_rule_ids)}, "
        f"obsolete_managed_rules_removed={removed}"
    )
  '';
  fastmailRoutesFilter = ''
    if (
      type == "array" and length > 0 and
      all(.[];
        type == "object" and
        ((keys | sort) == ["address", "name", "owner", "scope"]) and
        (.name | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
        (.address | type == "string" and contains("@")) and
        (.owner | type == "string" and length > 0) and
        (.scope == "private" or .scope == "family") and
        ((.scope == "family") == (.name == "family"))
      ) and
      ([.[].name] | length == (unique | length)) and
      ([.[].address] | length == (unique | length)) and
      ([.[] | select(.scope == "family")] | length == 1)
    ) then
      .
    else
      error("invalid Paperless Fastmail route document")
    end
  '';
  fastmailRoutesNormalizer = pkgs.writeShellApplication {
    name = "paperless-normalize-fastmail-routes";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
        echo "Usage: paperless-normalize-fastmail-routes FILE" >&2
        exit 64
      fi

      jq --compact-output --exit-status ${lib.escapeShellArg fastmailRoutesFilter} "$1"
    '';
  };
  commonShell = ''
    if [ "$(id -u)" -ne 0 ]; then
      echo "This Paperless administration command must run as root" >&2
      exit 77
    fi

    exec 9>${maintenanceLock}
    flock 9

    if ! systemctl is-active --quiet paperless-compose.service; then
      echo "Paperless Compose service is not active" >&2
      exit 69
    fi

    container_name="$(docker inspect --format '{{.Name}}' paperless_webserver)"
    project_name="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' paperless_webserver)"
    if [ "$container_name" != /paperless_webserver ] || [ "$project_name" != paperless ]; then
      echo "Refusing to use an unexpected Paperless container" >&2
      exit 69
    fi
  '';
  managementRuntimeInputs = [
    config.virtualisation.docker.package
    pkgs.coreutils
    pkgs.systemd
    pkgs.util-linux
  ];
  groupsScript = pkgs.writeText "paperless-bootstrap-groups.py" groupsPython;
  listUsersScript = pkgs.writeText "paperless-list-users.py" listUsersPython;
  promoteAdminScript = pkgs.writeText "paperless-promote-oidc-admin.py" promoteAdminPython;
  revokeAdminScript = pkgs.writeText "paperless-revoke-admin.py" revokeAdminPython;
  enableUserScript = pkgs.writeText "paperless-enable-user.py" enableUserPython;
  fastmailScript = pkgs.writeText "paperless-bootstrap-fastmail.py" fastmailPython;
  bootstrapGroups = pkgs.writeShellApplication {
    name = "paperless-bootstrap-groups";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      ${commonShell}
      docker exec paperless_webserver python manage.py shell \
        --command "$(<${groupsScript})"
    '';
  };
  listUsers = pkgs.writeShellApplication {
    name = "paperless-list-users";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      ${commonShell}
      docker exec paperless_webserver python manage.py shell \
        --command "$(<${listUsersScript})"
    '';
  };
  promoteAdmin = pkgs.writeShellApplication {
    name = "paperless-promote-oidc-admin";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      if [ "$#" -ne 1 ] || [ -z "$1" ]; then
        echo "Usage: paperless-promote-oidc-admin USERNAME" >&2
        exit 64
      fi
      export PAPERLESS_BOOTSTRAP_USERNAME="$1"
      ${commonShell}
      docker exec --env PAPERLESS_BOOTSTRAP_USERNAME paperless_webserver \
        python manage.py shell --command "$(<${promoteAdminScript})"
    '';
  };
  revokeAdmin = pkgs.writeShellApplication {
    name = "paperless-revoke-admin";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      if [ "$#" -ne 2 ] || [ "$1" != --disable-user ] || [ -z "$2" ]; then
        echo "Usage: paperless-revoke-admin --disable-user USERNAME" >&2
        exit 64
      fi
      export PAPERLESS_BOOTSTRAP_USERNAME="$2"
      ${commonShell}
      docker exec \
        --env PAPERLESS_BOOTSTRAP_USERNAME \
        paperless_webserver python manage.py shell \
        --command "$(<${revokeAdminScript})"
    '';
  };
  enableUser = pkgs.writeShellApplication {
    name = "paperless-enable-user";
    runtimeInputs = managementRuntimeInputs;
    text = ''
      if [ "$#" -ne 1 ] || [ -z "$1" ]; then
        echo "Usage: paperless-enable-user USERNAME" >&2
        exit 64
      fi
      export PAPERLESS_BOOTSTRAP_USERNAME="$1"
      ${commonShell}
      docker exec --env PAPERLESS_BOOTSTRAP_USERNAME paperless_webserver \
        python manage.py shell --command "$(<${enableUserScript})"
    '';
  };
  fastmailRunner = pkgs.writeShellApplication {
    name = "paperless-bootstrap-fastmail-runner";
    runtimeInputs = managementRuntimeInputs ++ [ fastmailRoutesNormalizer ];
    text = ''
      admin_username=""
      routes_file=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --admin-username)
            [ "$#" -ge 2 ] || { echo "Missing --admin-username value" >&2; exit 64; }
            admin_username="$2"
            shift 2
            ;;
          --routes-json)
            [ "$#" -ge 2 ] || { echo "Missing --routes-json value" >&2; exit 64; }
            routes_file="$2"
            shift 2
            ;;
          *)
            echo "Unknown argument: $1" >&2
            exit 64
            ;;
        esac
      done

      if [ -z "$admin_username" ] || [ -z "$routes_file" ]; then
        echo "Usage: paperless-bootstrap-fastmail --admin-username USERNAME --routes-json FILE" >&2
        exit 64
      fi
      if [ ! -f "$routes_file" ] || [ "$(stat --format=%u "$routes_file")" -ne 0 ]; then
        echo "Fastmail routes JSON must be a root-owned regular file" >&2
        exit 66
      fi
      routes_mode="$(stat --format=%a "$routes_file")"
      if (( (8#$routes_mode & 077) != 0 )); then
        echo "Fastmail routes JSON must not be readable by group or others" >&2
        exit 77
      fi
      if [ -z "''${PAPERLESS_FASTMAIL_USERNAME:-}" ] || [ -z "''${PAPERLESS_FASTMAIL_APP_PASSWORD:-}" ]; then
        echo "Required Fastmail credentials are missing from the Paperless environment" >&2
        exit 65
      fi

      routes_json="$(paperless-normalize-fastmail-routes "$routes_file")"

      export PAPERLESS_BOOTSTRAP_ADMIN_USERNAME="$admin_username"
      export PAPERLESS_BOOTSTRAP_ROUTES_JSON="$routes_json"
      ${commonShell}
      docker exec \
        --env PAPERLESS_BOOTSTRAP_ADMIN_USERNAME \
        --env PAPERLESS_BOOTSTRAP_ROUTES_JSON \
        --env PAPERLESS_FASTMAIL_USERNAME \
        --env PAPERLESS_FASTMAIL_APP_PASSWORD \
        paperless_webserver python manage.py shell \
        --command "$(<${fastmailScript})"
    '';
  };
  bootstrapFastmail = pkgs.writeShellApplication {
    name = "paperless-bootstrap-fastmail";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "This Paperless administration command must run as root" >&2
        exit 77
      fi
      exec systemd-run \
        --collect \
        --pipe \
        --quiet \
        --wait \
        --property=EnvironmentFile=${lib.escapeShellArg environmentFile} \
        ${fastmailRunner}/bin/paperless-bootstrap-fastmail-runner "$@"
    '';
  };
  bootstrapContractText = lib.concatStringsSep "\n" [
    groupsPython
    listUsersPython
    promoteAdminPython
    revokeAdminPython
    enableUserPython
    fastmailPython
    commonShell
  ];
in
{
  options.shulker.system.modules.paperless.bootstrapContractText = lib.mkOption {
    type = lib.types.lines;
    readOnly = true;
    internal = true;
    description = "Paperless bootstrap source exposed for evaluation contracts.";
  };

  options.shulker.system.modules.paperless.fastmailRoutesFilter = lib.mkOption {
    type = lib.types.lines;
    readOnly = true;
    internal = true;
    description = "Validated Fastmail route filter shared by bootstrap and native contracts.";
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.paperless.bootstrapContractText = bootstrapContractText;
    shulker.system.modules.paperless.fastmailRoutesFilter = fastmailRoutesFilter;

    environment.systemPackages = [
      bootstrapGroups
      bootstrapFastmail
      listUsers
      promoteAdmin
      revokeAdmin
      enableUser
    ];
  };
}
