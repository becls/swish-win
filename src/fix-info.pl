if ($#ARGV < 6)
{
    print "Usage: $0 internal-name product-name version company company-dir copyright-year filename\n\n";
    exit(-1);
}

$internal = $ARGV[0];
$product = $ARGV[1];
$version = $ARGV[2];
$company = $ARGV[3];
$companydir = $ARGV[4];
$year = $ARGV[5];

$filename = $ARGV[6];

$copyright = "\251 $year $company";

open INPUT, $filename;
@orig = <INPUT>;
$orig = join "", @orig;
close INPUT;

$new = $orig;
