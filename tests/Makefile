test: ismn01babj.ok ismc01rjtd.ok iusn01babj.ok

iusn01babj.ok:
	ruby ../bufrdump.rb -c A_IUSN01BABJ290000_C_RJTD_20191029025504_87.bufr | diff -u iusn01babj.c.txt -

ismn01babj.ok:
	ruby ../bufrdump.rb -c A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr | diff -u ismn01babj.c.txt -
	ruby ../bufrdump.rb -d A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr | diff -u ismn01babj.d.txt -
	ruby ../bufrdump.rb -j A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr | diff -u ismn01babj.j.txt -
	ruby ../bufr2synop.rb A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr | diff -u ismn01babj.t.txt -

ismc01rjtd.ok:
	ruby ../bufrdump.rb -d A_ISMC01RJTD270000_C_RJTD_20191027001931_55.bufr | diff -u ismc01rjtd.d.txt -
	ruby ../bufr2synop.rb A_ISMC01RJTD270000_C_RJTD_20191027001931_55.bufr | diff -u ismc01rjtd.t.txt -

overwrite:
	-ruby ../bufrdump.rb -c A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr > ismn01babj.c.txt
	-ruby ../bufrdump.rb -d A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr > ismn01babj.d.txt
	-ruby ../bufrdump.rb -j A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr > ismn01babj.j.txt
	-ruby ../bufr2synop.rb A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr > ismn01babj.t.txt
	-ruby ../bufrdump.rb -d A_ISMC01RJTD270000_C_RJTD_20191027001931_55.bufr > ismc01rjtd.d.txt
	-ruby ../bufr2synop.rb A_ISMC01RJTD270000_C_RJTD_20191027001931_55.bufr > ismc01rjtd.t.txt
	-ruby ../bufrdump.rb -c A_IUSN01BABJ290000_C_RJTD_20191029025504_87.bufr > iusn01babj.c.txt
