"""Primitive output-port regression; exact MULT12X12 parameters retained."""
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('mapped_cone_test',Path(__file__).resolve().parents[1]/'scripts/mapped_cone.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def test_mult12_output_follows_real_driver_without_replacing_arithmetic():
    text='''module parent (clk,reset,a,b,q);
input clk;
input reset;
input [11:0] a;
input [11:0] b;
output [23:0] q;
  MULT12X12 mul (.DOUT(q),.A(a),.B(b),.CLK({1'b0,clk}),.CE(2'b11),.RESET({1'b0,reset}));
defparam mul.MULT_RESET_MODE="ASYNC";
defparam mul.AREG_CLK="CLK0";
defparam mul.BREG_CLK="BYPASS";
defparam mul.OREG_CLK="BYPASS";
endmodule
'''
    graph=module.MappedCone(text,'parent')
    code,cells=graph.extract({'clk':'clk','reset':'reset','a':'a','b':'b'},{'q':'q'})
    assert len(cells)==1 and cells[0]['kind']=='MULT12X12'
    assert cells[0]['outs']=={'DOUT'} and len(cells[0]['ports']['DOUT'])==24
    assert ('AREG_CLK','"CLK0"') in cells[0]['params']
    assert 'MULT12X12 cell_0' in code and 'AREG_CLK="CLK0"' in code
    assert "assign q" in code and "1'bx" not in code


def test_multalu_all_three_outputs_keep_registered_cascade_parameters():
    text='''module parent (clk,reset,a,b,q,cas,soa);
input clk;
input reset;
input [26:0] a;
input [17:0] b;
output [47:0] q;
output [47:0] cas;
output [26:0] soa;
  MULTALU27X18 dsp (.DOUT(q),.CASO(cas),.SOA(soa),.A(a),.B(b),.CLK({1'b0,clk}),.RESET({1'b0,reset}));
defparam dsp.AREG_CLK="CLK0";
defparam dsp.CASI_SEL=1'b1;
endmodule
'''
    graph=module.MappedCone(text,'parent')
    code,cells=graph.extract({'clk':'clk','reset':'reset','a':'a','b':'b'},{'q':'q','cas':'cas','soa':'soa'})
    assert len(cells)==1 and cells[0]['outs']=={'DOUT','CASO','SOA'}
    assert ('CASI_SEL',"1'b1") in cells[0]['params']
    assert 'MULTALU27X18 cell_0' in code and "CASI_SEL=1'b1" in code
    assert "1'bx" not in code


def test_sdpx9b_follows_actual_memory_output_and_preserves_modes():
    text='''module parent (clk,a,b,di,q);
input clk;
input [13:0] a;
input [13:0] b;
input [35:0] di;
output [35:0] q;
  SDPX9B ram (.DO(q),.DI(di),.ADA(a),.ADB(b),.CLKA(clk),.CLKB(clk),.CEA(1'b1),.CEB(1'b1),.OCE(1'b0),.RESET(1'b0),.BLKSELA(3'b000),.BLKSELB(3'b000));
defparam ram.BIT_WIDTH_0=9;
defparam ram.BIT_WIDTH_1=9;
defparam ram.READ_MODE=1'b0;
defparam ram.RESET_MODE="SYNC";
endmodule
'''
    graph=module.MappedCone(text,'parent')
    code,cells=graph.extract({'clk':'clk','a':'a','b':'b','di':'di'},{'q':'q'})
    assert len(cells)==1 and cells[0]['outs']=={'DO'}
    assert ('READ_MODE',"1'b0") in cells[0]['params']
    assert 'SDPX9B cell_0' in code and 'RESET_MODE="SYNC"' in code
    assert "1'bx" not in code
