#! /bin/sh

. ../../testenv.sh

analyze --work=mylib and2.vhdl
analyze and3.vhdl tb_and3.vhdl
elab_simulate tb_and3
clean

synth --work=mylib and2.vhdl --work=work and3.vhdl -e and3 > syn_and3.vhdl
analyze syn_and3.vhdl tb_and3.vhdl
elab_simulate tb_and3
clean
clean mylib

echo "Test successful"
