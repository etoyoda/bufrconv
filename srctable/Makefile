all: table_b_bufr.v13 table_station

table_b_bufr.v13: b-diff.rb table_b_bufr-13 ../table_b_bufr
	ruby b-diff.rb table_b_bufr-13 ../table_b_bufr > table_b_bufr.v13

table_station: vola_compile.rb iso3166-gtsaa.txt
	ruby vola_compile.rb > table_station
