test: ismn01babj.ok

ismn01babj.ok:
	ruby ../bufrdump.rb -c A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr | diff -u ismn01babj.c.txt -
	ruby ../bufrdump.rb -d A_ISMN01BABJ280000_C_RJTD_20191028001731_81.bufr | diff -u ismn01babj.d.txt -
