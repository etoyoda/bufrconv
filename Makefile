test: all
	cd tests; $(MAKE) test

all: zip table_b_bufr.v13

table_b_bufr.v13: table_b_bufr srctable/table_b_bufr-13 srctable/b-diff.rb
	ruby srctable/b-diff.rb srctable/table_b_bufr-13 table_b_bufr > table_b_bufr.v13

overwrite:
	cd tests && $(MAKE) overwrite

zip: bufrconv.zip

FILES= LICENSE bufr2synop bufr2temp bufrscan.rb bufrdump.rb \
 table_b_bufr table_b_bufr.v13 table_d_bufr table_c11 table_station

bufr2synop: amalgamate.rb bufr2synop.rb bufrscan.rb bufrdump.rb output.rb
	ruby amalgamate.rb bufr2synop.rb bufrscan.rb bufrdump.rb output.rb > bufr2synop

bufr2temp: amalgamate.rb bufr2temp.rb bufrscan.rb bufrdump.rb output.rb
	ruby amalgamate.rb bufr2temp.rb bufrscan.rb bufrdump.rb output.rb > bufr2temp

bufrconv.zip: $(FILES)
	zip bufrconv.zip $(FILES)
