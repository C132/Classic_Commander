import zlib, struct

def read_png(path):
    d = open(path,'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat, pal, trns = 8, b'', None, None
    w=h=bd=ct=0
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]; typ = d[pos+4:pos+8]
        data = d[pos+8:pos+8+ln]; pos += 12+ln
        if typ==b'IHDR':
            w,h,bd,ct = struct.unpack('>IIBB', data[:10])
        elif typ==b'PLTE': pal=data
        elif typ==b'tRNS': trns=data
        elif typ==b'IDAT': idat+=data
        elif typ==b'IEND': break
    assert bd==8, bd
    ch = {0:1,2:3,3:1,4:2,6:4}[ct]
    raw = zlib.decompress(idat)
    stride = w*ch
    out = bytearray(h*stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if f==1:
            for i in range(ch, stride): line[i] = (line[i]+line[i-ch]) & 255
        elif f==2:
            for i in range(stride): line[i] = (line[i]+prev[i]) & 255
        elif f==3:
            for i in range(stride):
                a = line[i-ch] if i>=ch else 0
                line[i] = (line[i] + ((a+prev[i])>>1)) & 255
        elif f==4:
            for i in range(stride):
                a = line[i-ch] if i>=ch else 0
                b = prev[i]; c = prev[i-ch] if i>=ch else 0
                pp = a+b-c
                pa,pb,pc = abs(pp-a),abs(pp-b),abs(pp-c)
                pr = a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i] = (line[i]+pr) & 255
        out[y*stride:(y+1)*stride] = line
        prev = line
    # normalise to RGBA
    px = bytearray(w*h*4)
    for i in range(w*h):
        if ct==6: px[i*4:i*4+4] = out[i*4:i*4+4]
        elif ct==2: px[i*4:i*4+3] = out[i*3:i*3+3]; px[i*4+3]=255
        elif ct==0: v=out[i]; px[i*4:i*4+3]=bytes((v,v,v)); px[i*4+3]=255
        elif ct==4: v=out[i*2]; px[i*4:i*4+3]=bytes((v,v,v)); px[i*4+3]=out[i*2+1]
        elif ct==3:
            idx=out[i]; px[i*4:i*4+3]=pal[idx*3:idx*3+3]
            px[i*4+3]= trns[idx] if (trns and idx<len(trns)) else 255
    return w,h,px

def write_png(path, w, h, px):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += px[y*w*4:(y+1)*w*4]
    d = zlib.compress(bytes(raw), 9)
    def chunk(t, b):
        return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t+b) & 0xffffffff)
    out = b'\x89PNG\r\n\x1a\n'
    out += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    out += chunk(b'IDAT', d)
    out += chunk(b'IEND', b'')
    open(path,'wb').write(out)
