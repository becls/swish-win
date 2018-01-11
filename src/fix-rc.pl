#!/usr/bin/perl

do "./fix-info.pl";

$versionrc = $version;
$versionrc =~ s/\./,/g;
$new =~ s/(FILEVERSION )[0-9]+,[0-9]+,[0-9]+,[0-9]+/$1$versionrc/g;
$new =~ s/(PRODUCTVERSION )[0-9]+,[0-9]+,[0-9]+,[0-9]+/$1$versionrc/g;
$new =~ s/(VALUE \"CompanyName\", )\"[^\"]*\"/$1"$company"/g;
$new =~ s/(VALUE \"FileDescription\", )\"[^\"]*\"/$1"$product"/g;
$new =~ s/(VALUE \"FileVersion\", )\"[^\"]*\"/$1"$version"/g;
$new =~ s/(VALUE \"LegalCopyright\", )\"[^\"]*\"/$1"$copyright"/g;
$new =~ s/(VALUE \"InternalName\", )\"[^\"]*\"/$1"$internal.exe"/g;
$new =~ s/(VALUE \"ProductName\", )\"[^\"]*\"/$1"$product"/g;
$new =~ s/(VALUE \"ProductVersion\", )\"[^\"]*\"/$1"$version"/g;

open OUTPUT, ">" . $filename;
print OUTPUT $new;
close OUTPUT;
