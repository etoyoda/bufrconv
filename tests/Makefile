test: ismn01babj.ok ismc01rjtd.ok

ismn01babj.ok:
	ruby ../bufrdump.rb -c A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr | diff -u ismn01babj.c.txt -
	ruby ../bufrdump.rb -d A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr | diff -u ismn01babj.d.txt -

ismc01rjtd.ok:
	ruby ../bufrdump.rb -d A_ISMC01RJTD270000_C_RJTD_20191027001931_55.bufr | diff -u ismc01rjtd.d.txt
