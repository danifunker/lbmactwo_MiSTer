#!/usr/bin/env python3
"""HFS (classic, not HFS+) forensics for .vhd/.hda images.

Usage: hfs_forensics.py <image> [suspect_lba ...]
 - parses Apple Partition Map, finds HFS partition
 - parses MDB (+ alternate MDB), boot blocks
 - walks the catalog B-tree, builds file->extents map
 - reverse-maps suspect disk LBAs to owning file/fork/offset
 - validates B-tree node structure of catalog + extents trees
"""
import struct, sys

def be16(b, o): return struct.unpack_from('>H', b, o)[0]
def be32(b, o): return struct.unpack_from('>I', b, o)[0]

def pstr(b, o, maxlen):
    n = b[o]
    return b[o+1:o+1+min(n, maxlen)].decode('mac_roman', 'replace')

class HFS:
    def __init__(self, img, part_start_lba):
        self.img = img
        self.base = part_start_lba * 512
        mdb = img[self.base + 2*512 : self.base + 3*512]
        self.mdb = mdb
        if be16(mdb, 0) != 0x4244:
            raise ValueError(f"no BD sig in MDB (got {be16(mdb,0):04x})")
        self.drAtrb     = be16(mdb, 0x0A)
        self.drNmFls    = be16(mdb, 0x0C)
        self.drVBMSt    = be16(mdb, 0x0E)
        self.drNmAlBlks = be16(mdb, 0x12)
        self.drAlBlkSiz = be32(mdb, 0x14)
        self.drClpSiz   = be32(mdb, 0x18)
        self.drAlBlSt   = be16(mdb, 0x1C)
        self.drVN       = pstr(mdb, 0x24, 27)
        self.drXTFlSize = be32(mdb, 0x82)
        self.drXTExtRec = [(be16(mdb,0x86+i*4), be16(mdb,0x88+i*4)) for i in range(3)]
        self.drCTFlSize = be32(mdb, 0x92)
        self.drCTExtRec = [(be16(mdb,0x96+i*4), be16(mdb,0x98+i*4)) for i in range(3)]
        self.spab = self.drAlBlkSiz // 512   # sectors per alloc block

    def ab_to_lba(self, ab):
        """alloc block -> absolute image LBA"""
        return (self.base // 512) + self.drAlBlSt + ab * self.spab

    def read_fork(self, ext_rec, size, overflow=None, cnid=None, fork=0):
        """read a fork given its first extent record (+extents overflow tree)"""
        data = b''
        exts = list(ext_rec)
        if overflow is not None and cnid is not None:
            exts += overflow.get((cnid, fork), [])
        for (start, cnt) in exts:
            if cnt == 0: continue
            o = self.ab_to_lba(start) * 512
            data += self.img[o : o + cnt * self.drAlBlkSiz]
            if len(data) >= size: break
        return data[:size]

def parse_btree(data, name, report):
    """Parse B-tree file data; return list of (key, record) leaf records.
    Also validate node structure."""
    if len(data) < 512:
        report.append(f"  {name}: tree file too small ({len(data)})")
        return []
    # header node
    nd = data[0:512]
    ndType = nd[8]
    if ndType != 1:
        report.append(f"  {name}: node 0 is not a header node (type={ndType})")
        return []
    bthDepth   = be16(data, 14 + 0)
    bthRoot    = be32(data, 14 + 2)
    bthNRecs   = be32(data, 14 + 6)
    bthFNode   = be32(data, 14 + 10)
    bthLNode   = be32(data, 14 + 14)
    bthNodeSize= be16(data, 14 + 18)
    bthNNodes  = be32(data, 14 + 23)
    report.append(f"  {name}: depth={bthDepth} root={bthRoot} leafRecs={bthNRecs} "
                  f"firstLeaf={bthFNode} lastLeaf={bthLNode} nodeSize={bthNodeSize} nNodes={bthNNodes}")
    nodesz = bthNodeSize if bthNodeSize else 512
    nnodes = len(data) // nodesz
    leaves = []
    # walk leaf chain
    visited = set()
    node = bthFNode
    bad = 0
    while node != 0:
        if node in visited:
            report.append(f"  {name}: LOOP in leaf chain at node {node}")
            bad += 1; break
        visited.add(node)
        if node >= nnodes:
            report.append(f"  {name}: leaf chain points past EOF (node {node} >= {nnodes})")
            bad += 1; break
        o = node * nodesz
        fLink = be32(data, o); bLink = be32(data, o+4)
        ntype = data[o+8]; nrecs = be16(data, o+10)
        if ntype != 0xFF:
            report.append(f"  {name}: node {node} in leaf chain has type 0x{ntype:02x} (not leaf!) fLink={fLink}")
            bad += 1; break
        for r in range(nrecs):
            roff = be16(data, o + nodesz - 2 - 2*r)
            rend = be16(data, o + nodesz - 4 - 2*r) if r+1 < nrecs else None
            if roff >= nodesz:
                report.append(f"  {name}: node {node} rec {r} bad offset {roff}")
                bad += 1; continue
            leaves.append((node, data[o+roff : o + (rend if rend and rend>roff and rend<=nodesz else nodesz)]))
        node = fLink
    report.append(f"  {name}: walked {len(visited)} leaf nodes, {len(leaves)} records, anomalies={bad}")
    return leaves

def main():
    path = sys.argv[1]
    suspects = [int(x, 0) for x in sys.argv[2:]]
    img = open(path, 'rb').read()
    print(f"=== {path} ({len(img)} bytes, {len(img)//512} sectors)")

    # partition map
    parts = []
    if be16(img, 0) == 0x4552:  # 'ER'
        i = 1
        nmap = None
        while True:
            o = i * 512
            if be16(img, o) != 0x504D: break  # 'PM'
            cnt = be32(img, o+4)
            nmap = nmap or cnt
            start = be32(img, o+8); blkcnt = be32(img, o+12)
            pname = img[o+16:o+48].rstrip(b'\0').decode('ascii','replace')
            ptype = img[o+48:o+80].rstrip(b'\0').decode('ascii','replace')
            parts.append((start, blkcnt, pname, ptype))
            print(f"  part: start={start} cnt={blkcnt} name='{pname}' type='{ptype}'")
            i += 1
            if nmap and i > nmap: break
    hfs_parts = [p for p in parts if p[3] == 'Apple_HFS']
    if not hfs_parts:
        # maybe bare volume at LBA 0
        hfs_parts = [(0, len(img)//512, 'bare', 'Apple_HFS')]
        print("  (no partition map HFS entry; trying bare volume at 0)")
    start = hfs_parts[0][0]

    # boot blocks
    bb = img[start*512 : start*512+512]
    bbsig = be16(bb, 0)
    print(f"  boot block sig @part+0: 0x{bbsig:04X} {'(LK = bootable)' if bbsig==0x4C4B else '(NOT LK!)'}")
    if bbsig == 0x4C4B:
        print(f"    system='{pstr(bb,0x0A,15)}' shell='{pstr(bb,0x1A,15)}' debugger='{pstr(bb,0x2A,15)}'")

    v = HFS(img, start)
    print(f"  MDB: vol='{v.drVN}' atrb=0x{v.drAtrb:04X} ({'unmounted-clean' if v.drAtrb & 0x100 else 'DIRTY/mounted'}) "
          f"nmAlBlks={v.drNmAlBlks} alBlkSiz={v.drAlBlkSiz} alBlSt={v.drAlBlSt}")
    print(f"  catalog: size={v.drCTFlSize} ext={v.drCTExtRec}  extents-tree: size={v.drXTFlSize} ext={v.drXTExtRec}")

    # alternate MDB (2nd-to-last sector of partition)
    plen = hfs_parts[0][1]
    amdb_lba = start + plen - 2
    amdb = img[amdb_lba*512:(amdb_lba+1)*512]
    print(f"  alt MDB @lba {amdb_lba}: sig=0x{be16(amdb,0):04X} {'OK' if be16(amdb,0)==0x4244 else 'BAD'}")

    report = []
    # extents overflow tree first (needed for catalog fork if fragmented)
    xt_data = v.read_fork(v.drXTExtRec, v.drXTFlSize)
    xt_leaves = parse_btree(xt_data, "extents-tree", report)
    overflow = {}
    for node, rec in xt_leaves:
        if len(rec) < 7 + 12: continue
        klen = rec[0]
        fork = rec[1]; cnid = be32(rec, 2); startblk = be16(rec, 6)
        d = 8 if klen in (7,) else 1 + klen + (1 if (1+klen) % 2 else 0)
        exts = [(be16(rec, d+i*4), be16(rec, d+2+i*4)) for i in range(3)]
        overflow.setdefault((cnid, fork), []).extend(e for e in exts if e[1])
    # catalog
    ct_data = v.read_fork(v.drCTExtRec, v.drCTFlSize, overflow, 4, 0)
    ct_leaves = parse_btree(ct_data, "catalog", report)
    print("\n".join(report))

    # build file table
    files = []   # (cnid, parID, name, dataExts, dataSize, rsrcExts, rsrcSize)
    dirs = {2: ''}
    recs = []
    for node, rec in ct_leaves:
        if len(rec) < 2: continue
        klen = rec[0]
        if klen < 6: continue
        parID = be32(rec, 2)
        name = pstr(rec, 6, 31)
        # data starts after key, padded to even
        d = 1 + klen
        if d % 2: d += 1
        if d + 2 > len(rec): continue
        rtype = rec[d]
        if rtype == 1 and d+70 <= len(rec):      # directory
            cnid = be32(rec, d+6)
            dirs[cnid] = name
            recs.append(('dir', parID, name, cnid))
        elif rtype == 2 and d+102 <= len(rec):   # file
            cnid  = be32(rec, d+20)
            dlsiz = be32(rec, d+28)
            rlsiz = be32(rec, d+40)
            dext = [(be16(rec, d+74+i*4), be16(rec, d+76+i*4)) for i in range(3)]
            rext = [(be16(rec, d+86+i*4), be16(rec, d+88+i*4)) for i in range(3)]
            files.append((cnid, parID, name, dext, dlsiz, rext, rlsiz))
    print(f"  catalog: {len(files)} files, {len(dirs)-1} dirs")

    # reverse map: lba -> (file, fork, offset)
    def owner_of(lba):
        out = []
        for (cnid, parID, name, dext, dsz, rext, rsz) in files:
            for fork, (exts, sz) in (('data', (dext, dsz)), ('rsrc', (rext, rsz))):
                allext = list(exts) + overflow.get((cnid, 0x00 if fork=='data' else 0xFF), [])
                fo = 0
                for (st, cnt) in allext:
                    if cnt == 0: continue
                    lo = v.ab_to_lba(st); hi = lo + cnt*v.spab
                    if lo <= lba < hi:
                        out.append((name, dirs.get(parID, f'dir{parID}'), fork,
                                    fo + (lba-lo)*512, cnid))
                    fo += cnt * v.drAlBlkSiz
        return out

    for lba in suspects:
        own = owner_of(lba)
        # also: which alloc block, is it marked allocated?
        part_lba = lba - (v.base // 512)
        ab = (part_lba - v.drAlBlSt) // v.spab
        bm_off = v.base + v.drVBMSt*512
        byte = img[bm_off + ab//8]
        allocated = bool(byte & (0x80 >> (ab % 8)))
        print(f"  LBA {lba}: allocBlk={ab} bitmap={'ALLOCATED' if allocated else 'FREE'} -> "
              + ('; '.join(f"'{n}' (in '{p}') {f}-fork @+0x{o:X} cnid={c}" for n,p,f,o,c in own)
                 if own else "NOT in any catalog file extent"))

if __name__ == '__main__':
    main()
