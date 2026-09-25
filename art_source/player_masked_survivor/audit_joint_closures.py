"""Image comparison of matched renders with arm closures visible / hidden.
Run after render_review jobs named jointcap_<action>_<view>_<visible|hidden>.
This tests those poses/views only, not all possible occlusion cases.
"""
import bpy,json
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/player_masked_survivor/previews/'
cases=[(a,'front') for a in ['idle','sit_driver','climb_loop','QA_overhead','QA_deep_bend']]+[(a,'back') for a in ['idle','climb_loop','QA_overhead']]
results=[]
for action,view in cases:
    images=[bpy.data.images.load(OUT+'jointcap_'+action+'_'+view+'_'+end+'.png',check_existing=False) for end in ['visible','hidden']]
    a=list(images[0].pixels);b=list(images[1].pixels);maxdiff=0;count=0
    for i in range(0,len(a),4):
        d=max(abs(a[i+j]-b[i+j]) for j in range(3));maxdiff=max(maxdiff,d)
        if d>.02:count+=1
    results.append({'action':action,'view':view,'pixels_difference_over_0_02':count,'maximum_pixel_difference':maxdiff})
    for im in images:bpy.data.images.remove(im)
print('CAP_COMPARE='+json.dumps(results))
