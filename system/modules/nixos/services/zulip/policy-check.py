"""Read-only ingress acceptance check; run in Zulip's manage.py shell."""
from django.conf import settings
from zerver.models import Realm

# Zulip creates a separate internal realm for its system bots.
realms = list(
    Realm.objects.filter(deactivated=False).exclude(string_id=settings.SYSTEM_BOT_REALM)
)
if len(realms) != 1:
    raise RuntimeError('Expected exactly one active trial organization')
realm = realms[0]
if (
    realm.string_id
    or realm.enable_spectator_access
    or not realm.invite_required
    or not realm.require_e2ee_push_notifications
):
    raise RuntimeError('The root organization must be private, invitation-only, and require encrypted push')
print('Zulip trial organization policy passed')
