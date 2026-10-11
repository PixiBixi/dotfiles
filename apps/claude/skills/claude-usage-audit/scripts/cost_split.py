#!/usr/bin/env python3
"""Cost by token type and cache-read tax above 200k/300k context, last 30 days."""
import json,glob,os,sys
from datetime import datetime,timezone,timedelta
from collections import Counter, defaultdict
ROOT=os.path.expanduser('~/.claude/projects'); SINCE=datetime.now(timezone.utc)-timedelta(days=30)
P={"claude-opus-5-5":(4,20,.2),"claude-opus-5":(5,25,.5),"claude-opus-4-7":(5,25,.5),"claude-opus-4-8":(5,25,.5),"claude-sonnet-5-5":(2,10,.2),"claude-sonnet-5":(2,10,.2),"claude-haiku-4-5":(1,5,.1)}
def pr(m):
    for k in sorted(P,key=len,reverse=True):
        if m and m.startswith(k): return P[k]
    return (0,0,0)
seen=set(); bytype=Counter(); tax200=0; tax300=0; long_sess=Counter(); sess_rows=defaultdict(list)
for f in glob.glob(f'{ROOT}/**/*.jsonl',recursive=True):
    if os.path.getmtime(f)<SINCE.timestamp(): continue
    sub='/subagents/' in f
    for l in open(f,errors='replace'):
        try:d=json.loads(l)
        except:continue
        if d.get('type')!='assistant': continue
        t=datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
        if t<SINCE: continue
        m=d['message'];u=m.get('usage');k=(m.get('id'),d.get('requestId'))
        if not u or k in seen or m.get('model')in(None,'<synthetic>'):continue
        seen.add(k); i,o,cr=pr(m['model'])
        cc=u.get('cache_creation') or {}; w1=cc.get('ephemeral_1h_input_tokens',0) or 0; w5=(u.get('cache_creation_input_tokens',0) or 0)-w1
        bytype['output']+=u['output_tokens']*o/1e6; bytype['cache_read']+=u['cache_read_input_tokens']*cr/1e6
        bytype['write_1h']+=w1*i*2/1e6; bytype['write_5m']+=w5*i*1.25/1e6; bytype['input']+=u['input_tokens']*i/1e6
        if not sub:
            ctx=u['input_tokens']+u['cache_read_input_tokens']+u['cache_creation_input_tokens']
            tax200+=max(0,ctx-200e3)*cr/1e6; tax300+=max(0,ctx-300e3)*cr/1e6
            sess_rows[d.get('sessionId')].append(t)
for s,ts in sess_rows.items():
    days=len({x.astimezone().date() for x in ts})
    long_sess['1 day' if days==1 else '2-3 days' if days<=3 else '4+ days']+=1
print({k:round(v,2) for k,v in bytype.items()}, 'tax_above_200k',round(tax200,2),'tax_above_300k',round(tax300,2), dict(long_sess))
