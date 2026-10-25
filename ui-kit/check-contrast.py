#!/usr/bin/env python3
"""WCAG 2.1 AA contrast check for kit.css theme tokens and badge colour-mix pairs. Usage: python3 check-contrast.py"""
import re,os,sys
css=open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'kit.css')).read()
def block(sel):
    i=css.index(sel+'{');j=css.index('}',i);return dict(re.findall(r'--([\w-]+):(#[0-9a-fA-F]{6})',css[i:j]))
dark=block(':root,:root[data-theme=dark]');light=dict(dark);light.update(block(':root[data-theme=light],:root.light'))
rgb=lambda h:[int(h[i:i+2],16) for i in (1,3,5)]
hexs=lambda c:'#'+''.join('%02x'%round(x) for x in c)
mix=lambda a,p,b:hexs([x*p+y*(1-p) for x,y in zip(rgb(a),rgb(b))])
def L(h):
    c=[x/255 for x in rgb(h)];c=[x/12.92 if x<=.03928 else ((x+.055)/1.055)**2.4 for x in c];return .2126*c[0]+.7152*c[1]+.0722*c[2]
def cr(a,b):a,b=sorted([L(a),L(b)],reverse=True);return (a+.05)/(b+.05)
T=4.5;U=3
pairs=[('text','bg',T),('text','panel',T),('text','panel-2',T),('text','sel',T),('text-2','bg',T),('text-2','panel',T),('text-2','panel-2',T),
('muted','bg',T),('muted','panel',T),('muted','panel-2',T),('link','bg',T),('link','panel',T),('link','panel-2',T),('on-accent','accent',T),
('brand','bg',T),('brand','panel',T),('on-brand','brand',T),('ok','bg',T),('ok','panel',T),('warn','bg',T),('warn','panel',T),('err','bg',T),('err','panel',T),
('on-status','ok-bg',T),('on-status','warn-bg',T),('on-status','err-bg',T),('toast-info-fg','toast-info-bg',T),
('border-strong','bg',U),('border-strong','panel',U),('focus','bg',U),('focus','panel',U),('accent','bg',U),('accent','panel',U)]
BADGES=dict(green='#4cc27f',yellow='#e8c547',blue='#5a9cec',orange='#f08a3c',red='#ff5c5c',pink='#f27ab8',purple='#b38ae6',white='#ffffff',gold='#d4a72c',grey='#8d8b82')
fails=0;rows=[]
for name,t in (('dark',dark),('light',light)):
    for a,b,m in pairs:
        r=cr(t[a],t[b]);ok=r>=m;fails+=not ok;rows.append((name,a,t[a],b,t[b],r,m,ok))
    for k,bc in BADGES.items():
        if name=='dark': fg,bg=t['badge-fg'],mix(bc,.25 if k=='white' else .4,'#000000')
        else:
            bc2='#85837c' if k=='white' else bc; fg,bg=mix(bc2,.55,'#000000'),mix(bc2,.16,'#ffffff')
        r=cr(fg,bg);ok=r>=T;fails+=not ok;rows.append((name,'badge.'+k,fg,'bg',bg,r,T,ok))
for n,a,fa,b,fb,r,m,ok in rows: print(f"{n:5} {a:15} {fa} on {b:13} {fb}  {r:5.2f}:1 (min {m})  {'PASS' if ok else 'FAIL'}")
print(f"{len(rows)} pairs, {fails} failures");sys.exit(1 if fails else 0)
