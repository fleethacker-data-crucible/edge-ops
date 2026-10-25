import re
css=open(__import__('os').path.join(__import__('os').path.dirname(__file__),'kit.css')).read()
def block(sel):
    m=re.search(re.escape(sel)+r'\{(.*?)\}',css,re.S);return dict(re.findall(r'--(fh-[\w-]+):(#[0-9a-f]{6})',m.group(1)))
dark=block(':root,[data-theme=dark]');light=dict(dark);light.update(block('[data-theme=light]'))
def L(h):
    c=[int(h[i:i+2],16)/255 for i in (1,3,5)];c=[x/12.92 if x<=.03928 else ((x+.055)/1.055)**2.4 for x in c];return .2126*c[0]+.7152*c[1]+.0722*c[2]
def cr(a,b):a,b=sorted([L(a),L(b)],reverse=True);return (a+.05)/(b+.05)
pairs=[('fg','bg',4.5),('fg','surface',4.5),('muted','bg',4.5),('muted','surface',4.5),('link','bg',4.5),('link','surface',4.5),('accent','bg',4.5),('on-accent','accent',4.5),
('on-status','ok-bg',4.5),('on-status','warn-bg',4.5),('on-status','bad-bg',4.5),('on-status','info-bg',4.5),('fg','border-subtle',4.5),('border','bg',3),('border','surface',3),('focus','bg',3),('focus','surface',3),('accent','surface',3)]
bad=0
for name,t in (('dark',dark),('light',light)):
    print('##',name)
    for a,b,min_ in pairs:
        r=cr(t['fh-'+a],t['fh-'+b]);ok=r>=min_;bad+=not ok
        print(f"{a:10} {t['fh-'+a]} on {b:13} {t['fh-'+b]}  {r:5.2f}:1  need {min_}  {'PASS' if ok else 'FAIL'}")
print('FAILS',bad)
