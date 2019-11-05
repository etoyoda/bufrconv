test: all
	cd tests; $(MAKE) test

all: table_b_bufr.v13

table_b_bufr.v13: table_b_bufr srctable/table_b_bufr-13 srctable/b-diff.rb
	ruby srctable/b-diff.rb srctable/table_b_bufr-13 table_b_bufr > table_b_bufr.v13

overwrite:
	cd tests && $(MAKE) overwrite

zip: bufrconv.zip

FILES= LICENSE bufr2synop.rb bufrdump.rb bufrscan.rb table_b_bufr table_b_bufr.v13 table_d_bufr

bufrconv.zip: $(FILES)
	zip bufrconv.zip $(FILES)
