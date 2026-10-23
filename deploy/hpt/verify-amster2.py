import argparse,hashlib,json,os,secrets,shutil,struct,subprocess,sys,time
from pathlib import Path
import grpc
sys.path.insert(0,'/home/yurik/fido/ffido/probe')
from ffido.v1 import ffido_pb2 as p,ffido_pb2_grpc as g
from google.protobuf.empty_pb2 import Empty
os.umask(0o077)
parser=argparse.ArgumentParser(description='Isolated amster2 HPT charset verification; no production mail writes')
parser.add_argument('--image',required=True)
parser.add_argument('--worker',default='ffido-tosser:local')
parser.add_argument('--control-worker',default='ffido-tosser:before-hpt-transport-20261023')
options=parser.parse_args()
BASE=Path('/home/yurik/fido');WORK=BASE/'ffido/verification/hpt-charset';WORK.mkdir(parents=True,exist_ok=True)
ROOT=WORK/('isolated-cycle-'+time.strftime('%Y%m%d-%H%M%S'));ROOT.mkdir(exist_ok=False)
IMAGE=options.image;WORKER=options.worker;NAME='ffido-hpt-charset-fixture'
if subprocess.run(['docker','inspect',NAME],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:
 raise SystemExit('Fixture container name is already in use; existing container left untouched')
password=secrets.token_urlsafe(24)
def run(*args):
 r=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
 if r.returncode:raise RuntimeError(r.stdout.decode(errors='replace'))
 return r.stdout

def hpt(node,*args,old=False,enabled=True):
 image=options.control_worker if old else WORKER
 return run('docker','run','--rm','--network','none','--user','1000:1000','-e','FFIDO_HPT_KOI8_CP866='+('1' if enabled else '0'),'-v',str(ROOT)+':/fixture','--entrypoint','/opt/ffido-hpt/bin/hpt',image,'-c',f'/fixture/{node}/hpt.cfg',*args)

def records(base):
 if not base.with_suffix('.jdx').exists():return []
 idx=base.with_suffix('.jdx').read_bytes();hdr=base.with_suffix('.jhr').read_bytes();txt=base.with_suffix('.jdt').read_bytes();rows=[]
 for slot in range(len(idx)//8):
  at=struct.unpack_from('<I',idx,slot*8+4)[0]
  if at==0xffffffff:continue
  fields={};cur=at+76;end=cur+struct.unpack_from('<I',hdr,at+8)[0]
  while cur<end:
   lo,hi,n=struct.unpack_from('<HHI',hdr,cur);cur+=8;assert hi==0 and cur+n<=end
   fields.setdefault(lo,[]).append(hdr[cur:cur+n]);cur+=n
  off,n=struct.unpack_from('<II',hdr,at+60);rows.append((fields,txt[off:off+n]))
 return rows

def packets(node):
 result=[];files=[]
 for path in sorted((ROOT/node/'outbound').rglob('*')):
  if not path.is_file():continue
  data=path.read_bytes()
  if len(data)<60 or struct.unpack_from('<H',data,18)[0]!=2:continue
  files.append(path);at=58
  while data[at:at+2]!=b'\0\0':
   assert struct.unpack_from('<H',data,at)[0]==2
   at+=14;fields=[]
   for _ in range(5):
    end=data.index(0,at);fields.append(data[at:end]);at=end+1
   result.append(fields)
  assert at+2==len(data)
 return files,result

for node,addr,peer in [('sender','2:1/1','2:1/2'),('receiver','2:1/2','2:1/1')]:
 root=ROOT/node;root.mkdir();(root/'jam').mkdir()
 cfg=f'Name Charset fixture\nSysop Test\nLocation Isolated\nAddress {addr}\n'
 for key,folder in [('Inbound','inbound'),('ProtInbound','protinbound'),('Outbound','outbound'),('TempInbound','tmpin'),('TempOutbound','tmpout'),('LogFileDir','logs'),('DupeHistoryDir','dupes'),('NodelistDir','nodelist')]:
  (root/folder).mkdir();cfg+=f'{key} /fixture/{node}/{folder}\n'
 cfg+=f'MsgBaseDir /fixture/{node}/jam\nEchoTossLog /fixture/{node}/logs/toss.log\nRecodeMsgBase on\nOutTab /fixture/outtab\nInTab /fixture/intab\n'
 cfg+=f'Link Peer\nAKA {peer}\nOurAKA {addr}\nPassword fixture\nAllowEmptyPktPwd on\n'
 cfg+=f'Link Client\nAKA {addr}.1\nOurAKA {addr}\nSessionPwd {password}\n'
 for name in ['ordinary','utf-8']:
  cfg+=f'EchoArea {name} /fixture/{node}/jam/{name} -b JAM -dupeCheck off {peer} {addr}.1\n'
  run('docker','run','--rm','--network','none','--user','1000:1000','-v',str(ROOT)+':/fixture','--entrypoint','/usr/local/bin/ffido-create-jam',WORKER,f'/fixture/{node}/jam/{name}')
 for name in ('netmail','bad','dupe'):
  run('docker','run','--rm','--network','none','--user','1000:1000','-v',str(ROOT)+':/fixture','--entrypoint','/usr/local/bin/ffido-create-jam',WORKER,f'/fixture/{node}/jam/{name}')
 cfg+=f'NetmailArea NETMAIL /fixture/{node}/jam/netmail -b JAM\nBadArea BAD /fixture/{node}/jam/bad -b JAM\nDupeArea DUPE /fixture/{node}/jam/dupe -b JAM\n'
 (root/'hpt.cfg').write_text(cfg)
 (root/'areas.cfg').write_text(''.join(f'EchoArea {name} /fixture/{node}/jam/{name} -b JAM\n' for name in ('ordinary','utf-8')))
 config={'server':{'ip':'0.0.0.0','port':8080,'tls_certificate':'/etc/ffido/tls/server.pem','tls_private_key':'/etc/ffido/tls/server-key.pem'},'ftn':{'areacfg_path':f'/fixture/{node}/areas.cfg','jam_base_path':f'/fixture/{node}/jam','default_encoding':'KOI8-R','coordination_lock':f'/fixture/{node}/hpt.lock','jam_encoding_overrides':{'ordinary':'KOI8-R','utf-8':'UTF-8'}},'auth':{'hpt_config_path':f'/fixture/{node}/hpt.cfg','session_key_path':f'/fixture/{node}/session.key'},'database':{'metadata_path':f'/fixture/{node}/metadata.db'}}
 (root/'config.json').write_text(json.dumps(config))
# Preserve the established FTN soft-CR normalization in the production table.
shutil.copyfile(BASE/'spool/outkoi8alt',ROOT/'outtab')
shutil.copyfile(BASE/'spool/outaltkoi8',ROOT/'intab')

def start(node):
 run('docker','run','-d','--name',NAME,'--user','1000:1000','-p','127.0.0.1:18082:8080','-v',str(ROOT)+':/fixture','-v',str(BASE/'ffido/tls')+':/etc/ffido/tls:ro',IMAGE,f'/fixture/{node}/config.json')
 ch=grpc.secure_channel('127.0.0.1:18082',grpc.ssl_channel_credentials(),options=(('grpc.ssl_target_name_override','v1002682.hosted-by-vdsina.com'),));grpc.channel_ready_future(ch).result(timeout=30);stub=g.FfidoStub(ch)
 addr='2:1/1.1' if node=='sender' else '2:1/2.1'
 login=stub.Login(p.LoginRequest(name='Николай Ёж',address=addr,password=password),timeout=10);md=(('authorization','Bearer '+login.session_secret),)
 return ch,stub,md

def stop(ch,stub,md):
 stub.Logout(Empty(),metadata=md,timeout=10);ch.close()
 with (ROOT/'server.log').open('ab') as log:subprocess.run(['docker','logs',NAME],stdout=log,stderr=log,check=True)
 run('docker','rm','-f',NAME)

expected={};report={}
try:
 ch,stub,md=start('sender')
 for area,codec in [('ordinary','cp866'),('utf-8','utf-8')]:
  body='Новая проверка: Ёжик, ёлка, русский алфавит.\nАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ\nабвгдеёжзийклмнопрстуфхцчшщъыьэюя'+(' 😀 漢字' if area=='utf-8' else '')
  subject='Новая тема Ёё'+(' 😀' if area=='utf-8' else '')
  refs=[]
  for i in range(2):
   response=stub.CreateMessage(p.CreateMessageRequest(conference_id=area,operation_id=secrets.token_hex(16),to_name='Наталья Ёж',subject=subject+str(i),body=body,in_reply_to=refs[0].message_id if refs else ''),metadata=md,timeout=20)
   refs.append(response.message);message=stub.GetMessage(response.message,metadata=md,timeout=10)
   assert body.replace('Н','H') in message.body and message.subject==(subject+str(i)).replace('Н','H')
   expected[(area,message.subject)]=(message,codec)
  rows=records(ROOT/'sender/jam'/area);assert len(rows)==2
  local='koi8-r' if area=='ordinary' else 'utf-8'
  for f,text in rows:
   assert body.replace('Н','H').replace('\n','\r').encode(local) in text
   sent,_=expected[(area,f[6][0].decode(local))]
   assert f[2]==[sent.from_name.encode(local)] and f[3]==[sent.to_name.encode(local)]
   assert [x for x in f[2000] if x.startswith(b'CHRS:')]==[b'CHRS: '+(b'KOI8-R 2' if area=='ordinary' else b'UTF-8 4')]
 stop(ch,stub,md)
 # Capture exact new local messages before export; only flags/high-water may change.
 before={a:records(ROOT/'sender/jam'/a) for a in ('ordinary','utf-8')}
 shutil.copytree(ROOT/'sender',ROOT/'before-export')
 # Prove the regression exists in the previous HPT and opt-out preserves it.
 for control,old in [('control-old',True),('control-disabled',False)]:
  shutil.copytree(ROOT/'sender',ROOT/control)
  cfg=ROOT/control/'hpt.cfg';cfg.write_text(cfg.read_text().replace('/sender/','/'+control+'/'))
  hpt(control,'scan','-w',old=old,enabled=False)
  _,broken=packets(control);assert broken
  ordinary=[x for x in broken if x[4].startswith(b'AREA:ORDINARY\r')]
  utf8=[x for x in broken if x[4].startswith(b'AREA:UTF-8\r')]
  assert ordinary and all(b'\1CHRS: KOI8-R 2\r' in x[4] for x in ordinary)
  assert utf8 and all('😀'.encode() not in x[4] for x in utf8)
 # Invalid charset policy configuration must fail before changing message bases.
 for case in ('missing-outtab','unreadable-outtab','invalid-outtab','recode-off'):
  shutil.copytree(ROOT/'sender',ROOT/case)
  cfg=ROOT/case/'hpt.cfg';text=cfg.read_text().replace('/sender/','/'+case+'/')
  if case=='missing-outtab':text='\n'.join(line for line in text.splitlines() if not line.startswith('OutTab '))+'\n'
  elif case=='unreadable-outtab':text=text.replace('OutTab /fixture/outtab','OutTab /fixture/absent-table')
  elif case=='invalid-outtab':
   (ROOT/'invalid-outtab.table').write_text('0x100 0x41\n')
   text=text.replace('OutTab /fixture/outtab','OutTab /fixture/invalid-outtab.table')
  else:text=text.replace('RecodeMsgBase on','RecodeMsgBase off')
  cfg.write_text(text)
  hashes=lambda:{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in (ROOT/case/'jam').glob('*')}
  before_invalid=hashes()
  try:hpt(case,'scan','-w')
  except RuntimeError as error:
   expected_error=('File not found or no permission: /fixture/absent-table' if case=='unreadable-outtab' else 'FFIDO charset policy requires')
   assert expected_error in str(error),(case,str(error))
  else:raise AssertionError('Invalid charset configuration accepted: '+case)
  assert hashes()==before_invalid and not packets(case)[0]
 hpt('sender','scan','-w');files,wire=packets('sender')
 # The point copy produces the same message too; collect packets specifically for peer node 2.
 peer_files=[f for f in files if struct.unpack_from('<H',f.read_bytes(),2)[0]==2 and struct.unpack_from('<H',f.read_bytes(),52)[0]==0]
 assert peer_files, [str(f) for f in files]
 for f in files:
  if f not in peer_files:f.unlink()
 files,wire=packets('sender');assert len(wire)==4,(len(wire),[str(x) for x in files])
 for date,to,author,subject,text in wire:
  area=text.split(b'\r',1)[0][5:].decode().lower();codec='cp866' if area=='ordinary' else 'utf-8';message,_=expected[(area,subject.decode(codec))]
  assert author==message.from_name.encode(codec) and to==message.to_name.encode(codec)
  chrs=[line for line in text.split(b'\r') if line.startswith(b'\1CHRS:')]
  assert chrs==[b'\1CHRS: '+(b'CP866 2' if area=='ordinary' else b'UTF-8 4')],chrs
  assert message.body.replace('\n','\r').encode(codec) in text,(area,'body differs')
  if message.in_reply_to:assert b'\1REPLY:' in text
 # SMAPI normally serializes PID/address metadata again when setting SENT/SCANNED.
 # Payload, message/reply IDs and the stored local CHRS must stay unchanged.
 def payload(row):
  f,text=row
  return ([f.get(k) for k in (2,3,4,5,6)], [x for x in f.get(2000,[]) if x.startswith(b'CHRS:')],text)
 assert {a:list(map(payload,rows)) for a,rows in before.items()}=={a:list(map(payload,records(ROOT/'sender/jam'/a))) for a in before},'Local payload changed by export'
 exported={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
 hpt('sender','scan','-w');assert {str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in packets('sender')[0]}==exported,'Duplicate export'
 for n,f in enumerate(files):shutil.copyfile(f,ROOT/'receiver/protinbound'/f'fixture-{n}.pkt')
 hpt('receiver','toss')
 for area in ('ordinary','utf-8'):
  rows=records(ROOT/'receiver/jam'/area);assert len(rows)==2,(area,len(rows))
  codec='koi8-r' if area=='ordinary' else 'utf-8'
  for fields,text in rows:
   subject=fields[6][0].decode(codec);message,_=expected[(area,subject)]
   assert fields[2]==[message.from_name.encode(codec)] and fields[3]==[message.to_name.encode(codec)]
   assert message.body.replace('\n','\r').encode(codec) in text,(area,'received body differs')
 ch,stub,md=start('receiver')
 for area in ('ordinary','utf-8'):
  listed=stub.ListMessages(p.ListMessagesRequest(conference_id=area,page=p.PageRequest(limit=10),sort=p.MESSAGE_SORT_DATE_DESCENDING),metadata=md,timeout=10)
  assert len(listed.messages)==2
  for preview in listed.messages:
   got=stub.GetMessage(p.MessageReference(conference_id=area,message_id=preview.id),metadata=md,timeout=10);sent,_=expected[(area,got.subject)]
   assert got.from_name==sent.from_name and got.to_name==sent.to_name and sent.body in got.body
  report[area]={'messages':2,'reply':True,'jam_codec':('KOI8-R' if area=='ordinary' else 'UTF-8'),'packet_codec':('CP866' if area=='ordinary' else 'UTF-8'),'chrs_exact':True,'received_jam_and_rpc_match':True}
 stop(ch,stub,md)
 report.update(no_mailer=True,hpt_network='none',production_queues_not_mounted=True,repeat_scan_no_duplicates=True,local_payload_and_chrs_unchanged=True,previous_hpt_regression_reproduced=True,opt_out_preserves_upstream_behavior=True,invalid_config_rejected_before_jam_mutation=True)
 (WORK/'isolated-cycle-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
finally:
 if subprocess.run(['docker','inspect',NAME],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:
  with (ROOT/'server-failure.log').open('wb') as log:subprocess.run(['docker','logs',NAME],stdout=log,stderr=log)
  subprocess.run(['docker','rm','-f',NAME],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
