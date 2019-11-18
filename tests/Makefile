test: ismn01babj.ok ismc01rjtd.ok iusn01babj.ok iusc10rjtd.ok iusc60rjtd.ok ismd10rums.ok ismb01mxba.ok

ISMN01BABJ= A_ISMN01BABJ050000_C_RJTD_20191105001745_39.bufr
ISMC01RJTD= A_ISMC01RJTD270000_C_RJTD_20191027001931_55.bufr
IUSN01BABJ= A_IUSN01BABJ290000_C_RJTD_20191029025504_87.bufr
IUSC10RJTD= A_IUSC10RJTD280000_C_RJTD_20191028021231_41.bufr
IUSC60RJTD= A_IUSC60RJTD050000_C_RJTD_20191105010145_42.bufr
ISMB01MXBA= A_ISMB01MXBA061800_C_RJTD_20191106181332_94.bufr
ISMD10RUMS= A_ISMD10RUMS031200CCA_C_RJTD_20191106050332_71.bufr

iusn01babj.ok:
	ruby ../bufrdump.rb -x $(IUSN01BABJ) | diff -u iusn01babj.x.txt -
	ruby ../bufrdump.rb -c $(IUSN01BABJ) | diff -u iusn01babj.c.txt -
	ruby ../bufrdump.rb -j $(IUSN01BABJ) | diff -u iusn01babj.j.txt -
	ruby ../bufrdump.rb -d $(IUSN01BABJ) | diff -u iusn01babj.d.txt -
	ruby ../bufr2temp.rb $(IUSN01BABJ) | diff -u iusn01babj.t.txt -

iusc10rjtd.ok:
	ruby ../bufr2temp.rb $(IUSC10RJTD) | diff -u /dev/null -

iusc60rjtd.ok:
	ruby ../bufr2temp.rb $(IUSC60RJTD) | diff -u iusc60rjtd.t.txt -

ismn01babj.ok:
	ruby ../bufrdump.rb -x $(ISMN01BABJ) | diff -u ismn01babj.x.txt -
	ruby ../bufrdump.rb -c $(ISMN01BABJ) | diff -u ismn01babj.c.txt -
	ruby ../bufrdump.rb -d $(ISMN01BABJ) | diff -u ismn01babj.d.txt -
	ruby ../bufrdump.rb -j $(ISMN01BABJ) | diff -u ismn01babj.j.txt -
	ruby ../bufr2synop.rb $(ISMN01BABJ) | diff -u ismn01babj.t.txt -

ismc01rjtd.ok:
	ruby ../bufrdump.rb -d $(ISMC01RJTD) | diff -u ismc01rjtd.d.txt -
	ruby ../bufr2synop.rb $(ISMC01RJTD) | diff -u ismc01rjtd.t.txt -

ismb01mxba.ok:
	ruby ../bufrdump.rb -d $(ISMB01MXBA) | diff -u ismb01mxba.d.txt -

ismd10rums.ok:
	ruby ../bufr2synop.rb $(ISMD10RUMS) | diff -u ismd10rums.t.txt -

overwrite:
	-ruby ../bufrdump.rb -x $(ISMN01BABJ) > ismn01babj.x.txt
	-ruby ../bufrdump.rb -c $(ISMN01BABJ) > ismn01babj.c.txt
	-ruby ../bufrdump.rb -d $(ISMN01BABJ) > ismn01babj.d.txt
	-ruby ../bufrdump.rb -j $(ISMN01BABJ) > ismn01babj.j.txt
	-ruby ../bufr2synop.rb $(ISMN01BABJ) > ismn01babj.t.txt
	-ruby ../bufrdump.rb -d $(ISMC01RJTD) > ismc01rjtd.d.txt
	-ruby ../bufr2synop.rb $(ISMC01RJTD) > ismc01rjtd.t.txt
	-ruby ../bufrdump.rb -x $(IUSN01BABJ) > iusn01babj.x.txt
	-ruby ../bufrdump.rb -c $(IUSN01BABJ) > iusn01babj.c.txt
	-ruby ../bufrdump.rb -j $(IUSN01BABJ) > iusn01babj.j.txt
	-ruby ../bufrdump.rb -d $(IUSN01BABJ) > iusn01babj.d.txt
	-ruby ../bufr2temp.rb $(IUSN01BABJ) > iusn01babj.t.txt
	-ruby ../bufr2temp.rb $(IUSC60RJTD) > iusc60rjtd.t.txt
