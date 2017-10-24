BUILD := Release
NAME := $(shell ./software-info.pl software-internal-name)
PRODUCT := $(shell ./software-info.pl software-product-name)
VERSION := $(shell ./software-info.pl software-version)
COMPANY := $(shell ./software-info.pl software-company)
COMPANYDIR := $(shell ./software-info.pl software-company-dir)
YEAR := $(shell ./software-info.pl software-copyright-year)
INFO := software-info.ss
SFILES := $(shell find . -iname "*.ss" -printf '%p ')

.PHONY: build
build: exe32 ../bin/i3nt/$(NAME).boot

../bin/i3nt/$(NAME).boot: ../bin/i3nt/$(NAME).exe $(INFO) $(SFILES)
	find ../bin/i3nt/ -name "*.so" -delete
	./scheme32 --script build.ss $(NAME)

../bin/a6nt/$(NAME).boot: ../bin/a6nt/$(NAME).exe $(INFO) $(SFILES)
	find ../bin/a6nt/ -name "*.so" -delete
	./scheme64 --script build.ss $(NAME)

.PHONY: exe32 exe64
exe32: ../bin/i3nt/$(NAME).exe
exe64: ../bin/a6nt/$(NAME).exe

swish/../software-info.rc: $(INFO)
	./fix-rc.pl "$(NAME)" "$(PRODUCT)" "$(VERSION)" "$(COMPANY)" "$(COMPANYDIR)" "$(YEAR)" $@

../bin/i3nt/$(NAME).exe:\
  swish/Swish.sln\
  swish/Swish.vcxproj\
  $(shell ./relative-paths swish Swish.vcxproj)
	-find ../bin/i3nt/ -name "*.so" -delete
	./vs msbuild /nologo /v:q /t:rebuild /p:Configuration=$(BUILD),Platform=Win32,TargetName=$(NAME) swish/Swish.sln

../bin/a6nt/$(NAME).exe:\
  swish/Swish.sln\
  swish/Swish.vcxproj\
  $(shell ./relative-paths swish Swish.vcxproj)
	-find ../bin/a6nt/ -name "*.so" -delete
	./vs msbuild /nologo /v:q /t:rebuild /p:Configuration=$(BUILD),Platform=x64,TargetName=$(NAME) swish/Swish.sln

.PHONY: install
install: build install.nsi
	./makensis install.nsi

install.nsi: $(INFO)
	./fix-nsi.pl "$(NAME)" "$(PRODUCT)" "$(VERSION)" "$(COMPANY)" "$(COMPANYDIR)" "$(YEAR)" $@

.PHONY: clean
clean:
	-rm -f ../bin/{a6nt,i3nt}/$(NAME).{exe,pdb,boot}
	-find ../bin/{a6nt,i3nt}/ -name "*.so" -delete
	-rm -rf {swish,swish/x64}/{Debug,Hooks,Release}/
	-rm -f "../bin/$(PRODUCT) Install.exe"
	-find . -name "*.mo" -delete
	-find . -name "*.html" -and -not -iwholename "*/web-mats/*" -delete
