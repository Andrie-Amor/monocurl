#!/usr/bin/env perl
# make_icns.pl <appiconset-dir> <output.icns>
use strict;
use warnings;

my ($src, $out) = @ARGV;
die "usage: $0 <appiconset-dir> <output.icns>\n" unless $src && $out;

my @entries = (
    ["icp4", "monocurl-16.png"],
    ["ic11", "monocurl-32.png"],
    ["icp5", "monocurl-32.png"],
    ["ic12", "monocurl-64.png"],
    ["ic07", "monocurl-128.png"],
    ["ic13", "monocurl-256.png"],
    ["ic08", "monocurl-256.png"],
    ["ic14", "monocurl-512.png"],
    ["ic09", "monocurl-512.png"],
    ["ic10", "monocurl-1024.png"],
);

my $payload = "";
for my $entry (@entries) {
    open my $fh, "<:raw", "$src/$entry->[1]" or die "open $entry->[1]: $!";
    local $/;
    my $data = <$fh>;
    $payload .= $entry->[0] . pack("N", length($data) + 8) . $data;
}

open my $out_fh, ">:raw", $out or die "open $out: $!";
print {$out_fh} "icns", pack("N", length($payload) + 8), $payload;
