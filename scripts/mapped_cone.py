"""Extract actual primitive cones through mapped hierarchy, without forcing nodes.

Only explicitly named original producer/consumer interface nets can be cut as
inputs. Every other required net follows its real driver, including FF state.
Generated scalar names are aliases only; primitive parameters are unchanged.
"""
import re

NET=r'(\\\S+\s*|\w+)(?:\[(\d+)(?::(\d+))?\])?'
class MappedCone:
    def __init__(self,text,top):
        self.modules={m[1]:m[0] for m in re.finditer(r'\bmodule\s+(\w+)\s*\([\s\S]*?endmodule',text)}
        self.cells=[];self.drivers={};self.names={};self.root={}
        self.flatten(top,'',{},self.root)
    def flatten(self,name,path,aliases,keep=None):
        body=self.modules[name]
        decl={m[3].strip():(int(m[1]),int(m[2])) if m[1] else None for m in re.finditer(r'^\s*(?:input|output|inout|wire)\s+(?:\[(\d+):(\d+)\]\s*)?(\\\S+\s*|\w+)\s*;',body,re.M)}
        nets={n:aliases.get(n,[path+n+(f'[{i}]' if w else '') for i in range(w[1],w[0]+1)] if w else [path+n]) for n,w in decl.items()}
        if keep is not None:keep.update(nets)
        def bits(expr):
            expr=expr.strip()
            if not expr:return []
            if expr.startswith('{'):
                out=[]
                for x in reversed(expr[1:-1].split(',')):out+=bits(x)
                return out
            lit=re.fullmatch(r"(\d+)'([bh])([0-9a-fA-FxXzZ]+)",expr)
            if lit:
                w=int(lit[1]);v=lit[3].lower()
                if 'x' in v or 'z' in v:return ["1'bx"]*w
                v=int(v,2 if lit[2]=='b' else 16);return [f"1'b{(v>>i)&1}" for i in range(w)]
            m=re.fullmatch(NET,expr);assert m,('unsupported actual expression',path,expr)
            n=m[1].strip();assert n in nets,('undeclared mapped net',path,n)
            if m[2] is None:return nets[n]
            lo=int(m[3] or m[2]);hi=int(m[2]);base=decl[n][1] if decl[n] else 0
            return [nets[n][i-base] for i in range(lo,hi+1)]
        param_map={}
        for pm in re.finditer(r'^\s*defparam\s+(\\\S+\s*|\w+)\s*\.\s*(\w+)\s*=\s*([^;]+);',body,re.M):
            param_map.setdefault(pm[1].strip(),[]).append((pm[2],pm[3]))
        for m in re.finditer(r'^\s*(?!module\b)(\w+)\s+(\\\S+\s*|\w+)\s*\(([\s\S]*?)\);',body,re.M):
            kind,inst,raw=m.groups();inst=inst.strip()
            if kind=='module':continue
            ports={p:bits(e) for p,e in re.findall(r'\.(\w+|\\\S+\s*)\(([^)]*)\)',raw)}
            ports={p.strip():v for p,v in ports.items()}
            if kind in self.modules:self.flatten(kind,path+inst+'/',ports);continue
            outs={'F'} if kind.startswith('LUT') else {'SUM','COUT'} if kind=='ALU' else {'Q'} if kind.startswith('DFF') else {'V'} if kind=='VCC' else {'G'} if kind=='GND' else {'O'} if kind.startswith(('MUX2_LUT','INV')) else set()
            # Official gw5a MULT12X12: DOUT[23:0] is the sole output.
            # Preserve every mapped parameter/input, including register clocks.
            if kind=='MULT12X12':outs={'DOUT'}
            # Official gw5a MULTALU27X18 has all three output buses.
            if kind=='MULTALU27X18':outs={'DOUT','CASO','SOA'}
            # Official gw5a SDPX9B: preserve actual synchronous RAM and INIT.
            if kind=='SDPX9B':outs={'DO'}
            params=param_map.get(inst,[])
            cell=dict(kind=kind,path=path+inst,ports=ports,outs=outs,params=params)
            idx=len(self.cells);self.cells.append(cell)
            for pin in outs:
                for b in ports.get(pin,[]):
                    assert b not in self.drivers,('multiple drivers',b)
                    self.drivers[b]=idx
    def extract(self,inputs,outputs,constant_inputs=None):
        # inputs/outputs maps human wrapper pin -> exact root declaration.
        binds={};selected=set();outmap={}
        for pin,n in inputs.items():
            assert n in self.root,('missing original boundary',n)
            for i,b in enumerate(self.root[n]):
                assert b not in binds,('duplicate cut',b)
                binds[b]=pin+(f'[{i}]' if len(self.root[n])>1 else '')
        constants={}
        for pin,value in (constant_inputs or {}).items():
            for i,b in enumerate(self.root[inputs[pin]]):constants[b]=(value>>i)&1
        constant_busy=set();pruned=[]
        def lut_info(cell):
            if not cell['kind'].startswith('LUT'):return None
            init=dict(cell['params']).get('INIT');assert init,cell['path']
            mm=re.fullmatch(r"(\d+)'h([0-9a-fA-F]+)",init)
            assert mm,init
            return int(cell['kind'][3:]),int(mm[2],16)
        def value(b):
            if b in constants:return constants[b]
            if b in ["1'b0","1'b1"]:return int(b[-1])
            if b in binds or b not in self.drivers or b in constant_busy:return None
            cell=self.cells[self.drivers[b]];info=lut_info(cell)
            if cell['kind'] in ['VCC','GND']:return int(cell['kind']=='VCC')
            if not info:return None
            constant_busy.add(b);width,init=info
            known={i:value(cell['ports']['I'+str(i)][0]) for i in range(width)}
            constant_busy.remove(b)
            values={(init>>a)&1 for a in range(1<<width) if all(v is None or (a>>i)&1==v for i,v in known.items())}
            if len(values)==1:constants[b]=next(iter(values));return constants[b]
            return None
        trail=[]
        def visit(b):
            if b in binds or b.startswith("1'"):return
            assert b in self.drivers,('missing real driver',b,trail[:24],trail[-8:])
            idx=self.drivers[b]
            if idx in selected:return
            selected.add(idx);cell=self.cells[idx]
            assert cell['outs'],('inspect non-primitive driver',cell)
            trail.append(cell['path'])
            info=lut_info(cell);irrelevant=set()
            if info:
                width,init=info;known={i:value(cell['ports']['I'+str(i)][0]) for i in range(width)}
                for i in range(width):
                    if known[i] is not None:continue
                    addresses=[a for a in range(1<<width) if not ((a>>i)&1) and all(v is None or (a>>j)&1==v for j,v in known.items())]
                    if all(((init>>a)&1)==((init>>(a|(1<<i)))&1) for a in addresses):irrelevant.add('I'+str(i))
                if irrelevant:pruned.append(dict(instance=cell['path'],known=known,irrelevant=sorted(irrelevant)))
            for pin,vals in cell['ports'].items():
                if pin not in cell['outs']:
                    if pin not in irrelevant:
                        for v in vals:visit(v)
            trail.pop()
        for pin,n in outputs.items():
            assert n in self.root,n
            vals=self.root[n];outmap[pin]=vals
            for b in vals:visit(b)
        allbits={b for i in selected for vals in self.cells[i]['ports'].values() for b in vals if b not in binds and not b.startswith("1'")}
        aliases={b:f'n{i}' for i,b in enumerate(sorted(allbits))}
        def wire(b):return binds.get(b,aliases.get(b,b))
        lines=['wire '+','.join(aliases.values())+';']
        undriven=[b for b in allbits if b not in self.drivers or self.drivers[b] not in selected]
        lines+=['assign '+wire(b)+"=1'bx;" for b in sorted(undriven)]
        for idx in sorted(selected):
            cell=self.cells[idx];inst=f'cell_{idx}'
            def expr(vals):
                vv=[wire(v) for v in vals]
                return vv[0] if len(vv)==1 else '{'+','.join(reversed(vv))+'}' if vv else ''
            lines.append(cell['kind']+' '+inst+' ('+','.join('.'+p+'('+expr(v)+')' for p,v in cell['ports'].items())+');')
            lines += ['defparam '+inst+'.'+p+'='+v+';' for p,v in cell['params']]
        for pin,vals in outmap.items():
            for i,v in enumerate(vals):lines.append('assign '+pin+(f'[{i}]' if len(vals)>1 else '')+'='+wire(v)+';')
        self.pruning_proof=pruned
        return '\n'.join(lines),[self.cells[i] for i in sorted(selected)]

