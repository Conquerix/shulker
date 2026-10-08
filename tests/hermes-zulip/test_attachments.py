import httpx
import pytest

@pytest.mark.asyncio
async def test_redirect_never_downloads_external_attachment(adapter):
    visited=[]
    def respond(request):
        visited.append(str(request.url))
        if request.url.host=='zulip.example.test':
            return httpx.Response(302,headers={'location':'https://outside.example/secret.txt'})
        return httpx.Response(200,content=b'not allowed')
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        adapter._client=client
        result=await adapter._materialize_message_attachments({'id':17},'[x](/user_uploads/a/test.txt)')
    assert not result['media_urls']
    assert len(visited)==1


def test_mirror_cannot_be_enabled(adapter, tmp_path):
    adapter.attachment_public_base_url='https://public.example'
    adapter.attachment_public_dir=tmp_path/'public'
    image=tmp_path/'image.png'
    image.write_bytes(b'private image')
    assert adapter._publish_attachment_for_external_fetch(image, media_type='image/png', message_id='17', filename='image.png') is None


def test_plaintext_same_host_is_not_an_authenticated_upload(adapter):
    assert adapter._zulip_upload_links('[x](http://zulip.example.test/user_uploads/a/test.txt)') == []

@pytest.mark.asyncio
async def test_forged_length_cannot_bypass_stream_limit(adapter):
    adapter.attachment_max_bytes=4
    def respond(request):
        return httpx.Response(200, headers={'content-length':'1'}, content=b'too many bytes')
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        adapter._client=client
        result=await adapter._materialize_message_attachments({'id':18},'[x](/user_uploads/a/test.txt)')
    assert not result['media_urls']
