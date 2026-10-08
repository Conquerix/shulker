"""Fixed-origin HTTP transport never forwards credentials or accepts oversized output."""
import httpx
import pytest
from broker.client import AgentServerClient, BackendError
from broker.policy import Policy

@pytest.fixture
def policy():
    return Policy('https://coding-api.shulker.link', '8dcb2360-3c3f-4e30-bb75-626b5f7d27d6', 10010, 'https://code.shulker.link')

@pytest.mark.parametrize('url', ['http://coding.test', 'https://user:pass@coding.test', 'https://coding.test/path', 'https://coding.test?key=secret'])
def test_bad_backend_origin_denied(url):
    with pytest.raises(ValueError): Policy(url, '8dcb2360-3c3f-4e30-bb75-626b5f7d27d6', 10010, 'https://code.shulker.link')

def test_redirect_never_forwards_key(policy):
    seen=[]
    def handler(request):
        seen.append(request)
        return httpx.Response(302, headers={'Location':'https://other.example.test/'})
    client=AgentServerClient(policy, 'synthetic', transport=httpx.MockTransport(handler))
    with pytest.raises(BackendError): client.inspect('00000000-0000-0000-0000-000000000001')
    assert len(seen)==1

def test_streamed_response_limit(policy):
    client=AgentServerClient(policy, 'synthetic', transport=httpx.MockTransport(lambda r: httpx.Response(200, content=b'x'*262145)))
    with pytest.raises(BackendError): client.inspect('00000000-0000-0000-0000-000000000001')
