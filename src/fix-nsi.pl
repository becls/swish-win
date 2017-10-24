#!/usr/bin/perl

do "fix-info.pl";

$new =~ s/define COMPANY_DIR .*/define COMPANY_DIR "$companydir"/g;
$new =~ s/define INTERNAL_NAME .*/define INTERNAL_NAME "$internal"/g;
$new =~ s/define PRODUCT_NAME .*/define PRODUCT_NAME "$product"/g;
$new =~ s/define PRODUCT_PUBLISHER .*/define PRODUCT_PUBLISHER "$company"/g;
$new =~ s/define PRODUCT_VERSION .*/define PRODUCT_VERSION "$version"/g;
$new =~ s/define YEAR .*/define YEAR "$year"/g;

open OUTPUT, ">" . $filename;
print OUTPUT $new;
close OUTPUT;
