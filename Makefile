test: all
	cd tests; $(MAKE) test

all: table_b_bufr.v13

table_b_bufr.v13: table_b_bufr srctable/table_b_bufr-13 srctable/b-diff.rb
	ruby srctable/b-diff.rb srctable/table_b_bufr-13 table_b_bufr > table_b_bufr.v13