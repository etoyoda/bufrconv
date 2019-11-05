test: ismn01babj.ok ismc01rjtd.ok iusn01babj.ok

ISMN01BABJ= A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr
ISMC01RJTD= A_ISMC01RJTD270000_C_RJTD_20191027001931_55.bufr
IUSN01BABJ= A_IUSN01BABJ290000_C_RJTD_20191029025504_87.bufr

iusn01babj.ok:
	ruby ../bufrdump.rb -c $(IUSN01BABJ) | diff -u iusn01babj.c.txt -

ismn01babj.ok:
	ruby ../bufrdump.rb -c $(ISMN01BABJ) | diff -u ismn01babj.c.txt -
	ruby ../bufrdump.rb -d $(ISMN01BABJ) | diff -u ismn01babj.d.txt -
	ruby ../bufrdump.rb -j $(ISMN01BABJ) | diff -u ismn01babj.j.txt -
	ruby ../bufr2synop.rb $(ISMN01BABJ) | diff -u ismn01babj.t.txt -

ismc01rjtd.ok:
	ruby ../bufrdump.rb -d $(ISMC01RJTD) | diff -u ismc01rjtd.d.txt -
	ruby ../bufr2synop.rb $(ISMC01RJTD) | diff -u ismc01rjtd.t.txt -

overwrite:
	-ruby ../bufrdump.rb -c $(ISMN01BABJ) > ismn01babj.c.txt
	-ruby ../bufrdump.rb -d $(ISMN01BABJ) > ismn01babj.d.txt
	-ruby ../bufrdump.rb -j $(ISMN01BABJ) > ismn01babj.j.txt
	-ruby ../bufr2synop.rb $(ISMN01BABJ) > ismn01babj.t.txt
	-ruby ../bufrdump.rb -d $(ISMC01RJTD) > ismc01rjtd.d.txt
	-ruby ../bufr2synop.rb $(ISMC01RJTD) > ismc01rjtd.t.txt
	-ruby ../bufrdump.rb -c $(IUSN01BABJ) > iusn01babj.c.txt
