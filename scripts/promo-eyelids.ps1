function Get-PromoEyelidsFilter([string]$Start, [string]$Length) {
    # Reuse the shape and feather of player/san_eyelids.gdshader in post-production.
    $closure = "clip((T-$Start)/$Length,0,1)"
    $opening = '1.08-(1.12+0.15*pow(2*(X+0.5)/W-1,2))*ld(1)'
    $lid = "st(0,$closure);st(1,ld(0)*ld(0)*(3-2*ld(0)));st(2,$opening);st(3,clip((abs(2*(Y+0.5)/H-1)-ld(2)+0.035)/0.07,0,1));"
    $visible = '(1-ld(3)*ld(3)*(3-2*ld(3)))'
    "geq=lum='${lid}16+(lum(X,Y)-16)*${visible}':cb='${lid}128+(cb(X,Y)-128)*${visible}':cr='${lid}128+(cr(X,Y)-128)*${visible}':enable='gte(t,$Start)'"
}
