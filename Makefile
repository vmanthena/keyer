SUBDIRS=jack-tcl-wrap lib/wrap lib/morse
all::
	for dir in $(SUBDIRS); do (cd $$dir && $(MAKE) all); done

clean::
	@find . -name '*~' -exec rm -f \{} \;
	for dir in $(SUBDIRS); do (cd $$dir && $(MAKE) clean); done

all-clean::
	@find . -name '*~' -exec rm -f \{} \;
	for dir in $(SUBDIRS); do (cd $$dir && $(MAKE) all-clean); done
