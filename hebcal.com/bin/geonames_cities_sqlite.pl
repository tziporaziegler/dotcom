#!/usr/bin/perl -w

use strict;
use DBI;
use Carp;

die "usage: $0 geonames.sqlite3 countryInfo.txt cities15000.txt admin1CodesASCII.tx \n" unless @ARGV == 4;

my $file = shift;
my $in_country = shift;
my $in_cities = shift;
my $in_admin1 = shift;

my $dbh = DBI->connect("dbi:SQLite:dbname=$file", "", "",
		       { RaiseError => 1, AutoCommit => 0 })
    or die $DBI::errstr;

do_sql($dbh, qq{DROP TABLE IF EXISTS geoname});

do_sql($dbh, qq{CREATE TABLE geoname ( 
    geonameid int PRIMARY KEY, 
    name nvarchar(200), 
    asciiname nvarchar(200), 
    alternatenames nvarchar(4000), 
    latitude decimal(18,15), 
    longitude decimal(18,15), 
    fclass nchar(1), 
    fcode nvarchar(10), 
    country nvarchar(2), 
    cc2 nvarchar(60), 
    admin1 nvarchar(20), 
    admin2 nvarchar(80), 
    admin3 nvarchar(20), 
    admin4 nvarchar(20), 
    population int, 
    elevation int, 
    gtopo30 int, 
    timezone nvarchar(40), 
    moddate date);});

do_sql($dbh, qq{DROP TABLE IF EXISTS admin1});

do_sql($dbh, qq{CREATE TABLE admin1 (
    key TEXT PRIMARY KEY,
    name nvarchar(200) NOT NULL,
    asciiname nvarchar(200) NOT NULL,
    geonameid int NOT NULL
    );});

do_sql($dbh, qq{DROP TABLE IF EXISTS country});

do_sql($dbh, qq{CREATE TABLE country (
  ISO TEXT PRIMARY KEY,
  ISO3 TEXT NOT NULL,
  IsoNumeric TEXT NOT NULL,
  fips TEXT NOT NULL,
  Country TEXT NOT NULL,
  Capital TEXT NOT NULL,
  Area INT NOT NULL,
  Population INT NOT NULL,
  Continent TEXT NOT NULL,
  tld TEXT NOT NULL,
  CurrencyCode TEXT NOT NULL,
  CurrencyName TEXT NOT NULL,
  Phone TEXT NOT NULL,
  PostalCodeFormat TEXT,
  PostalCodeRegex TEXT,
  Languages TEXT NOT NULL,
  geonameid INT NOT NULL,
  neighbours TEXT NOT NULL,
  EquivalentFipsCode TEXT NOT NULL
);});

do_file($dbh,$in_country,"country",19);
do_file($dbh,$in_cities,"geoname",19);
do_file($dbh,$in_admin1,"admin1",4);

do_sql($dbh, qq{DROP TABLE IF EXISTS geoname_fulltext});

do_sql($dbh, qq{CREATE VIRTUAL TABLE geoname_fulltext
USING fts3(geonameid int, name text, population int
);
});

do_sql($dbh, qq{INSERT INTO geoname_fulltext
SELECT g.geonameid, g.asciiname||', '||a.asciiname||', '||c.Country, g.population
FROM geoname g, admin1 a, country c
WHERE g.country = c.ISO
AND g.country||'.'||g.admin1 = a.key
});

$dbh->commit;
$dbh->disconnect();
undef $dbh;

exit(0);

sub do_sql {
    my($dbh,$sql) = @_;

    print STDERR $sql, "\n";
    $dbh->do($sql);
    $dbh->commit;
}

sub do_file {
    my($dbh,$infile,$table_name,$expected_fields) = @_;

    my $sql = "INSERT INTO $table_name VALUES (?";
    for (my $i = 0; $i < $expected_fields - 1; $i++) {
	$sql .= ",?";
    }
    $sql .= ")";
    print STDERR $sql, "\n";
    my $sth = $dbh->prepare($sql) or die $dbh->errstr;

    my $fh;
    open($fh, "<:encoding(UTF-8)", $infile)
	or die "cannot open < $infile: $!";

    my $i = 0;
    while(<$fh>) {
	chomp;
	next if /^#/;
	my @a = split(/\t/, $_, -1);
	my $actual = scalar(@a);
	if ($actual != $expected_fields) {
	    carp "$infile:$.: got $actual fields (expected $expected_fields)\n";
	    next;
	}
	my $rv = $sth->execute(@a) or die $dbh->errstr;
	if (0 == $i++ % 1000) {
	    $dbh->commit;
	}
    }
    close($fh);
    $sth->finish;
    undef $sth;
    $dbh->commit;
}
