# CosmosTcl
This repository contains the start of a parser for the BALL COSMOS telemetry configuration
files. The parser is not complete- there are TODOs in the code listing the missing
features.


The idea is that a TCL program could encode or decode binary data by reading the telemetry definitions,
and that a similar parser could be written for the command files.


This is somwhat hampered by the fact that this format may make use of Ruby source code files,
and these files may depend on COSMOS to work, so this format is not really meaningful outside
of the COSMOS system.
