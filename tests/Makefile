test: iujn30babj.ok ismd02edzw.ok ismn01babj.ok ismc01rjtd.ok iusn01babj.ok iusc10rjtd.ok iusc60rjtd.ok ismd10rums.ok ismb01mxba.ok isml01rjtd.ok iuad01egrr.ok

ISMN01BABJ= A_ISMN01BABJ050000_C_RJTD_20191105001745_39.bufr
ISMC01RJTD= A_ISMC01RJTD270000_C_RJTD_20191027001931_55.bufr
IUSN01BABJ= A_IUSN01BABJ290000_C_RJTD_20191029025504_87.bufr
IUSC10RJTD= A_IUSC10RJTD280000_C_RJTD_20191028021231_41.bufr
IUSC60RJTD= A_IUSC60RJTD050000_C_RJTD_20191105010145_42.bufr
ISMB01MXBA= A_ISMB01MXBA061800_C_RJTD_20191106181332_94.bufr
ISMD10RUMS= A_ISMD10RUMS031200CCA_C_RJTD_20191106050332_71.bufr
ISML01RJTD= A_ISML01RJTD060000_C_RJTD_20191106001931_24.bufr
ISMD02EDZW= A_ISMD02EDZW060000_C_RJTD_20191106000231_58.bufr
IUJN30BABJ= A_IUJN30BABJ121800_C_RJTD_20191112180000.bufr
IUAD01EGRR= A_IUAD01EGRR260724_C_RJTD_20191126072631_95.bufr

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

isml01rjtd.ok:
	ruby ../bufr2synop.rb $(ISML01RJTD) | diff -u isml01rjtd.t.txt -

ismd02edzw.ok:
	ruby ../bufr2synop.rb $(ISMD02EDZW) | diff -u ismd02edzw.t.txt -

iujn30babj.ok:
	ruby ../bufr2pilot.rb $(IUJN30BABJ) | diff -u iujn30babj.t.txt -

iuad01egrr.ok:
	ruby ../bufr2amdar.rb $(IUAD01EGRR) | diff -u iuad01egrr.t.txt -

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
