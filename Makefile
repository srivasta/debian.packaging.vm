# what Emacs version to build VM for.
# Allowed values are 18 and 19.
# Version 18 of Emacs is UNSUPPORTED.
# In fact all versions of Emacs prior to 19.34 for Emacs and
# prior to 19.14 for XEmacs are unsupported.  For v20 XEmacs
# EMACS_VERSION should remain 19.
#
EMACS_VERSION = 19

# what emacs is called on your system
EMACS = emacs

# where the Info file should go
INFODIR = /usr/local/lib/emacs/info

# where the vm.elc, tapestry.elc, etc. files should go
LISPDIR = /usr/local/lib/emacs/site-lisp

# where the toolbar pixmaps should go.
# vm-toolbar-pixmap-directory must point to the same place.
# vm-image-directory must point to the same place.
PIXMAPDIR = /usr/local/lib/emacs/etc/vm

############## no user servicable parts beyond this point ###################

# no csh please
SHELL = /bin/sh

# byte compiler options
BYTEOPTS = ./vm-byteopts.el

# have to preload the files that contain macro definitions or the
# byte compiler will compile everything that references them
# incorrectly.  also preload a file that sets byte compiler options.
PRELOADS = -l $(BYTEOPTS) -l ./vm-message.el -l ./vm-misc.el -l ./vm-vars.el -l ./vm-version.el

# compile with noninteractive and relatively clean environment
BATCHFLAGS = -batch -q -no-site-file

# files that contain key macro definitions.  almost everything
# depends on them because the byte-compiler inlines macro
# expansions.  everything also depends on the byte compiler
# options file since this might do odd things like turn off
# certain compiler optimizations.
CORE = vm-message.el vm-misc.el vm-byteopts.el

OBJECTS = \
    vm-delete.elc vm-digest.elc vm-easymenu.elc vm-edit.elc vm-folder.elc \
    vm-imap.elc vm-license.elc vm-mark.elc vm-menu.elc vm-message.elc \
    vm-mime.elc vm-minibuf.elc vm-misc.elc vm-mouse.elc \
    vm-motion.elc vm-page.elc vm-pop.elc vm-reply.elc \
    vm-save.elc \
    vm-search.elc vm-sort.elc vm-summary.elc vm-startup.elc vm-thread.elc \
    vm-toolbar.elc vm-undo.elc \
    vm-user.elc vm-vars.elc vm-version.elc vm-virtual.elc vm-window.elc

SOURCES = \
    vm-delete.el vm-digest.el vm-easymenu.el vm-edit.el vm-folder.el \
    vm-imap.el vm-license.el vm-mark.el vm-menu.el vm-message.el \
    vm-mime.el vm-minibuf.el vm-misc.el vm-mouse.el \
    vm-motion.el vm-page.el vm-pop.el vm-reply.el vm-save.el \
    vm-search.el vm-sort.el vm-startup.el vm-summary.el vm-thread.el \
    vm-toolbar.el vm-undo.el \
    vm-user.el vm-vars.el vm-version.el vm-virtual.el vm-window.el

vm:	vm.elc

vm.elc:	autoload

noautoload:	$(OBJECTS) tapestry.elc
	@echo "building vm.elc (with all modules included)..."
	@cat $(OBJECTS) tapestry.elc > vm.elc

autoload:	vm-autoload.elc $(OBJECTS) tapestry.elc
	@echo "building vm.elc (with all modules set to autoload)..."
	@echo "(require 'vm-startup)" > vm.elc
	@echo "(require 'vm-vars)" >> vm.elc
	@echo "(require 'vm-version)" >> vm.elc
	@echo "(require 'vm-autoload)" >> vm.elc

all:	vm.info vm

debug:	$(SOURCES) tapestry.el
	@echo "building vm.elc (uncompiled, no autoloads)..."
	@cat $(SOURCES) tapestry.el > vm.elc

install:	all
	cp vm.info $(INFODIR)/vm
	cp *.elc $(LISPDIR)
	cp pixmaps/*.xpm $(PIXMAPDIR)

clean:
	rm -f vm-autoload.el vm-autoload.elc $(OBJECTS) tapestry.elc

vm.info:	vm.texinfo
	@echo "making vm.info..."
	@$(EMACS) $(BATCHFLAGS) -insert vm.texinfo -l texinfmt -f texinfo-format-buffer -f save-buffer

vm-autoload.elc:	$(SOURCES)
	@echo scanning sources to build autoload definitions...
	@echo "(provide 'vm-autoload)" > vm-autoload.el
	@$(EMACS) $(BATCHFLAGS) -l ./make-autoloads -f print-autoloads $(SOURCES) >> vm-autoload.el
	@echo compiling vm-autoload.el...
	@$(EMACS) $(BATCHFLAGS) -l $(BYTEOPTS) -f batch-byte-compile vm-autoload.el

vm-delete.elc:	vm-delete.el $(CORE)
	@echo compiling vm-delete.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-delete.el

vm-digest.elc:	vm-digest.el $(CORE)
	@echo compiling vm-digest.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-digest.el

vm-edit.elc:	vm-edit.el $(CORE)
	@echo compiling vm-edit.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-edit.el

vm-folder.elc:	vm-folder.el $(CORE)
	@echo compiling vm-folder.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-folder.el

vm-imap.elc:	vm-imap.el $(CORE)
	@echo compiling vm-imap.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-imap.el

vm-license.elc:	vm-license.el $(CORE)
	@echo compiling vm-license.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-license.el

vm-mark.elc:	vm-mark.el $(CORE)
	@echo compiling vm-mark.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-mark.el

vm-menu.elc:	vm-menu.el vm-easymenu.el $(CORE)
	@echo compiling vm-menu.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -l ./vm-easymenu.el -f batch-byte-compile vm-menu.el

vm-message.elc:	vm-message.el $(CORE)
	@echo compiling vm-message.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-message.el

vm-minibuf.elc:	vm-minibuf.el $(CORE)
	@echo compiling vm-minibuf.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-minibuf.el

vm-mime.elc:	vm-mime.el $(CORE)
	@echo compiling vm-mime.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-mime.el

vm-misc.elc:	vm-misc.el $(CORE)
	@echo compiling vm-misc.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-misc.el

vm-mouse.elc:	vm-mouse.el $(CORE)
	@echo compiling vm-mouse.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-mouse.el

vm-motion.elc:	vm-motion.el $(CORE)
	@echo compiling vm-motion.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-motion.el

vm-page.elc:	vm-page.el $(CORE)
	@echo compiling vm-page.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-page.el

vm-pop.elc:	vm-pop.el $(CORE)
	@echo compiling vm-pop.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-pop.el

vm-reply.elc:	vm-reply.el $(CORE)
	@echo compiling vm-reply.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-reply.el

vm-save.elc:	vm-save.el $(CORE)
	@echo compiling vm-save.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-save.el

vm-search.el:	Makefile vm-search$(EMACS_VERSION).el
	@echo making vm-search.el...
	@{ test -f vm-search.el && \
	  cmp -s vm-search.el vm-search$(EMACS_VERSION).el && \
	  touch vm-search.el ; } || \
	 { rm -f vm-search.el; cp vm-search$(EMACS_VERSION).el vm-search.el ; }

vm-search.elc:	vm-search.el $(CORE)
	@echo compiling vm-search.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-search.el

vm-sort.elc:	vm-sort.el $(CORE)
	@echo compiling vm-sort.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-sort.el

vm-startup.elc:	vm-startup.el $(CORE)
	@echo compiling vm-startup.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-startup.el

vm-summary.elc:	vm-summary.el $(CORE)
	@echo compiling vm-summary.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-summary.el

vm-thread.elc:	vm-thread.el $(CORE)
	@echo compiling vm-thread.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-thread.el

vm-toolbar.elc:	vm-toolbar.el $(CORE)
	@echo compiling vm-toolbar.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-toolbar.el

vm-undo.elc:	vm-undo.el $(CORE)
	@echo compiling vm-undo.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-undo.el

vm-user.elc:	vm-user.el $(CORE)
	@echo compiling vm-user.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-user.el

vm-vars.elc:	vm-vars.el $(CORE)
	@echo compiling vm-vars.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-vars.el

vm-version.elc:	vm-version.el $(CORE)
	@echo compiling vm-version.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-version.el

vm-virtual.elc:	vm-virtual.el $(CORE)
	@echo compiling vm-virtual.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-virtual.el

vm-window.elc:	vm-window.el $(CORE)
	@echo compiling vm-window.el...
	@$(EMACS) $(BATCHFLAGS) $(PRELOADS) -f batch-byte-compile vm-window.el

tapestry.elc:	tapestry.el
	@echo compiling tapestry.el...
	@$(EMACS) $(BATCHFLAGS) -l $(BYTEOPTS) -f batch-byte-compile tapestry.el

vm-easymenu.elc:	vm-easymenu.el
	@echo compiling vm-easymenu.el...
	@$(EMACS) $(BATCHFLAGS) -l $(BYTEOPTS) -f batch-byte-compile vm-easymenu.el
