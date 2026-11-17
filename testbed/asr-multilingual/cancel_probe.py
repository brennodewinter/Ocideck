"""Explicit loopback-only TLS cancellation measurement; no quality assertion."""
import argparse
import http.client,ssl,time,json
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('fixture',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
# Test-only loopback certificate; never used by OciDeck transport.
context=ssl._create_unverified_context()
def connection():return http.client.HTTPSConnection('127.0.0.1',8443,context=context,timeout=20)
boundary='ocideck-cancel-reference-boundary'
def multipart(audio):
 parts=[]
 for name,data in [('diarize',b'false'),('language_mode',b'mixed'),('file',audio)]:
  disposition=f'Content-Disposition: form-data; name="{name}"'+('; filename="audio.wav"' if name=='file' else '')
  parts.append(f'--{boundary}\r\n{disposition}\r\n\r\n'.encode()+data+b'\r\n')
 return b''.join(parts)+f'--{boundary}--\r\n'.encode()
headers={'Content-Type':f'multipart/form-data; boundary={boundary}'}
path='/ocideck-asr/v1/transcribe'
request=connection();request.request('POST',path,multipart(args.fixture.read_bytes()),headers)
observed=[]
for _ in range(30):
 probe=connection();probe.request('POST',path,multipart(b'invalid').replace(b'\r\nmixed\r\n', b'\r\nunsupported\r\n'),headers);response=probe.getresponse();status=response.status;response.read();probe.close();observed.append(status)
 if status==429:break
 time.sleep(.1)
if 429 not in observed:raise RuntimeError('Did not observe active model task; cancellation proof invalid')
time.sleep(2)
started=time.monotonic();request.close()
for _ in range(150):
 probe=connection();probe.request('POST',path,multipart(b'invalid').replace(b'\r\nmixed\r\n', b'\r\nunsupported\r\n'),headers);response=probe.getresponse();status=response.status;response.read();probe.close();observed.append(status)
 if status==422:break
 if status!=429:raise RuntimeError('Unexpected probe response')
 time.sleep(.1)
elapsed=time.monotonic()-started
report={'scope':'real TLS client disconnect during actual small-model inference; worker capacity becomes available','busy_seen':429 in observed,'busy_wait_before_disconnect_seconds':2,'released_after_disconnect':status==422,'release_seconds':elapsed,'statuses':observed,'tls_certificate':'test-only self-signed loopback; verification bypass limited to this probe'}
args.output.write_text(json.dumps(report,indent=2)+'\n')
print(report)
if not report['released_after_disconnect']:raise RuntimeError('worker did not stop at a segment boundary')
