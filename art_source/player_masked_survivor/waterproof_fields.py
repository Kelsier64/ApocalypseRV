"""Original PU-coated workwear folds in the current 1.60 m rest space."""
import math
from mathutils import Vector

def g(x,w):return math.exp(-(x/w)**2)
def gate(x,a,b):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def lobe(a,c,w=.7):return math.exp((math.cos(a-c)-1)/w)

def sleeve_uv(p):
    x,y,z=p;d=Vector((.630,-.073,-.773)).normalized()
    q=Vector((abs(x)-.217,y,z-1.2718667));t=q.dot(d)
    u=Vector((.773,0,.630)).normalized()
    return t,math.atan2(q.y-d.y*t,q.dot(u))

def waterproof_height(p):
    x,y,z=p;ax=abs(x)
    if ax>.245 and z>.76:
        t,a=sleeve_uv(p);h=0
        for c,w,amp,shift in [(.170,.008,.0022,.5),(.205,.007,-.0020,1.1),(.234,.009,.0025,.1),(.271,.006,-.0020,.8),(.306,.008,.0023,1.7),(.352,.007,-.0017,2.4),(.396,.009,.0021,.2),(.432,.006,-.0013,1.4)]:
            h+=amp*g(t-c-.014*math.sin(a+shift),w)*lobe(a,-1.1+shift*.35,.95)
        return h*gate(t,.105,.145)*(1-gate(t,.43,.48))
    if z<.85:
        xc=.095+(.112-.095)*max(0,min(1,(.80-z)/.67));a=math.atan2(y+.012,ax-xc);h=0
        for c,w,amp,shift in [(.70,.009,.0023,.3),(.65,.007,-.0016,1.4),(.588,.010,.0027,.8),(.535,.007,-.0025,1.8),(.492,.010,.0030,.2),(.448,.006,-.0020,1.5),(.411,.009,.0027,.9),(.362,.007,-.0023,2.1),(.303,.009,.0021,.5),(.261,.006,-.0016,1.2)]:
            h+=amp*g(z-c-.020*math.sin(a+shift),w)*lobe(a,-1.6+shift*.6,.75)
        # Compression fans behind the knee, fainter when seen from the front.
        for c in [.429,.452,.478]:h+=.0016*g(z-c-.014*math.sin(a*2),.006)*lobe(a,1.57,.45)
        return h*gate(z,.235,.26)*(1-gate(z,.72,.82))
    a=math.atan2(y/.115,x/.19);h=0
    for c,w,amp,shift in [(1.015,.009,.0019,.7),(1.053,.006,-.0017,1.1),(1.087,.010,.0022,.2),(1.133,.007,-.0015,2.1),(1.178,.010,.0014,1.8)]:
        h+=amp*g(z-c-.025*math.sin(a*2+shift),w)*(.3+.7*lobe(a,0,.7)+.7*lobe(a,math.pi,.7))
    # Lower back stays tucked in: no belt-level displaced fat ridge.
    return h*gate(z,.976,1.01)*(1-gate(z,1.20,1.28))

def waterproof_offset(p,name):
    x,y,z=p
    if 'arm' in name:
        t,a=sleeve_uv(p)
        elbow=.250
        cut=(1-gate(t,.231,.247)) if 'upper_arm' in name else gate(t,.263,.281)
        cuff=1-gate(t,.431,.469)
        h=.0035*math.sin(t*118+1.3*math.sin(a+.4))*lobe(a,-.6,1.1)*gate(t,.145,.177)*cut*cuff
        sg=1 if x>=0 else -1
        return Vector((sg*.773*math.cos(a)*h,math.sin(a)*h,.630*math.cos(a)*h))
    if 'thigh' in name or 'shin' in name:
        xc=.095+(.112-.095)*max(0,min(1,(.80-z)/.67));a=math.atan2(y+.012,abs(x)-xc)
        edge=gate(z,.49,.515)*(1-gate(z,.71,.754)) if 'thigh' in name else gate(z,.242,.272)*(1-gate(z,.405,.433))
        h=.0042*math.sin(z*82+1.4*math.sin(a+.6))*lobe(a,-.8,1.0)*edge
        return Vector(((1 if x>=0 else -1)*math.cos(a)*h,math.sin(a)*h,0))
    if name=='body_torso':
        a=math.atan2(y/.115,x/.19)
        h=.0023*math.sin(z*84+math.sin(a*2))*gate(z,1.045,1.08)*(1-gate(z,1.17,1.215))
        return Vector((math.cos(a)*h,math.sin(a)*h,0))
    return Vector()
