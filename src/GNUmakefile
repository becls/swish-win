SHELL := /bin/bash -o pipefail
BUILD := Release
NAME := $(shell ./get-software-info software-internal-name)
PRODUCT := $(shell ./get-software-info software-product-name)
VERSION := $(shell ./get-software-info software-version)
COMPANY := $(shell ./get-software-info software-company)
COMPANYDIR := $(shell ./get-software-info software-company-dir)
YEAR := $(shell ./get-software-info software-copyright-year)
INFO := software-info.ss
SFILES := $(shell find . -iname "*.ss" -printf '%p ')

.PHONY: build
build: exe32 ../bin/i3nt/$(NAME).boot

../bin/i3nt/$(NAME).boot: ../bin/i3nt/$(NAME).exe $(INFO) $(SFILES)
	find ../bin/i3nt/ -name "*.so" -delete
	../bin/i3nt/$(NAME).exe -b scheme.boot --libdirs ".;;..\\bin\\i3nt" --script build.ss $(NAME) 2>&1 | ./build-filter

../bin/a6nt/$(NAME).boot: ../bin/a6nt/$(NAME).exe $(INFO) $(SFILES)
	find ../bin/a6nt/ -name "*.so" -delete
	../bin/a6nt/$(NAME).exe -b scheme.boot --libdirs ".;;..\\bin\\a6nt" --script build.ss $(NAME) 2>&1 | ./build-filter

.PHONY: exe32 exe64
exe32: ../bin/i3nt/$(NAME).exe
exe64: ../bin/a6nt/$(NAME).exe

swish/../software-info.rc: $(INFO)
	./fix-rc "$(NAME)" "$(PRODUCT)" "$(VERSION)" "$(COMPANY)" "$(COMPANYDIR)" "$(YEAR)" $@

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
	./makensis /V2 install.nsi

install.nsi: $(INFO)
	./fix-nsi "$(NAME)" "$(PRODUCT)" "$(VERSION)" "$(COMPANY)" "$(COMPANYDIR)" "$(YEAR)" $@

.PHONY: clean
clean:
	-rm -f ../bin/{a6nt,i3nt}/$(NAME).{exe,pdb,boot}
	-find ../bin/{a6nt,i3nt}/ -name "*.so" -delete
	-rm -rf {swish,swish/x64}/{Debug,Hooks,Release}/
	-rm -f "../bin/$(PRODUCT) Install.exe"
	-find . -name "*.mo" -delete
	-find . -name "*.html" -and -not -iwholename "*/web-mats/*" -delete
