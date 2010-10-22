#!/usr/bin/perl

# 2010 Haruka Kataoka

# usage
# 1. prepare text data file. (example: cdlist.txt)
# 2. insert CD and launch iTunes.
# 3. execute this
#    ./text2iTunesCDNames.pl < cdlist.txt

use strict;
use warnings;

use utf8;
use Encode;

binmode STDIN , ':utf8';
binmode STDOUT, ':utf8';

# order of album property
my @album_scheme = qw(
	artist
	composer
	name
	_disc_number
	genre
	_year
	_compilation
	_gapless
);
# order of track property
my @track_scheme = qw(
	name
	artist
);

# AppleScript skeltons
my $script_skel_album = <<EOS;
tell application "iTunes"
	set myCD to first source whose kind is audio CD
	set myCDList to audio CD playlist 1 of myCD
	
	tell myCDList
		[%property%]
		[%track%]
	end tell
end tell
EOS
my $script_skel_track = <<EOS;
		tell audio CD track [%number%] of myCDList
			[%property%]
		end tell
EOS

# -------------------------------------------------

# parse text data to cd data structure
sub parse_text($) {
	my $a = shift;
	my $cd = {
		_tracks => []
	};
	my $cd_head = $cd;
	my $track = 0;
	my $scheme_head = 0;
	my $gapless_album = 0;
	foreach my $line (@$a){
		chomp $line;
		if ($line =~ /^:(\d*)$/) {     # set head to a Track
			$track = $1 ? $1 : ($track + 1);
			if (! ref $cd->{_tracks}->[$track]) {
				$cd->{_tracks}->[$track] = {};
			}
			$cd_head = $cd->{_tracks}->[$track];
			$scheme_head = 0;
			$cd_head->{gapless} = \1 if $gapless_album;
		}elsif($track == 0) { # album data
			my $scheme = $album_scheme[$scheme_head++];
			next if $line eq '';
			if ($scheme eq '_disc_number') {
				if ($line =~ m|(\d+)(?:/(\d+))?|) {
					$cd_head->{'disc number'} = $1;
					$cd_head->{'disc count'} = $2 if $2;
				}else{
					warn "disc number must be '1/3' format.($line)";
				}
			}elsif ($scheme eq '_year') {
				if ($line =~ /(\d+)/) {
					$cd_head->{year} = $1;
				}else{
					warn "album year must be numeric.($line)";
				}
			}elsif ($scheme eq '_compilation') {
				if ($line =~ /[:：][Yは]/i) {
					$cd_head->{compilation} = \1;
				}
			}elsif ($scheme eq '_gapless') {
				if ($line =~ /[:：][Yは]/i) {
					$gapless_album = 1;
				}
			}else{
				$cd_head->{$scheme} = $line;
			}
		}else{                # track data
			my $scheme = $track_scheme[$scheme_head++];
			next if $line eq '';
			$cd_head->{$scheme} = $line;
		}
	}
	
	return $cd;
}

# create applescript from cd data structure
sub create_script($) {
	my $cd = shift;
	my $script = $script_skel_album;
	while(my($k, $v) = each(%$cd)) {
		next if $k eq '_tracks';
		skel_expand(\$script, 'property', script_set($k, $v));
	}
	skel_final (\$script, 'property');
	for(my $i = 1; $i < @{ $cd->{_tracks} }; $i++) {
		my $track = $script_skel_track;
		skel_expand(\$track, 'number', $i);
		skel_final (\$track, 'number');
		while(my($k, $v) = each(%{ $cd->{_tracks}->[$i] })) {
			skel_expand(\$track, 'property', script_set($k, $v));
		}
		skel_final (\$track, 'property');
		skel_expand(\$script, 'track', $track);
	}
	skel_final (\$script, 'track');
	return \$script;
}
sub skel_expand($$$) {
	my $skel  = shift;
	my $key   = shift;
	my $value = shift;
	$$skel =~ s/\[\%$key\%\]/$value . "[%$key%]"/eg;
}
sub skel_final($$) {
	my $skel = shift;
	my $key  = shift;
	$$skel =~ s/\[\%$key\%\]//g;
}
sub script_set($$) {
	my $key = shift;
	my $val = shift;
	if (ref $val) {
		$val = $$val ? 'true' : 'false';
	}elsif ($val =~ /\D/) {
		$val = qq("$val");
	}
	return "set $key to $val\n";
}

# exec script
sub osaexec($) {
	my $script = shift;
	open (my $osa, "| osascript -") or die "cannot open osascript";
	print $osa Encode::encode('utf8', $$script);
	close $osa;
}

# main
sub main() {
	my @in = <>;
	my $cddata = parse_text \@in;
	my $script = create_script $cddata;
	osaexec $script;
	#print $$script;
}

main;

# -------------------------------------------------

__END__

# this is sample AppleScript to change CD names.

tell application "iTunes"
	set myCD to first source whose kind is audio CD
	set myCDList to audio CD playlist 1 of myCD
	
	tell myCDList
		set artist to "artist"
		set composer to "composer"
		set name to "name"
		set disc count to 1
		set disc number to 3
		set genre to "Educational"
		set year to 2010
		set compilation to true
		
		tell audio CD track 1 of myCDList
			set name to "title1"
			set artist to "artist1"
			set gapless to true
		end tell
	end tell
end tell

# this is sample data
album artist
album composer
album name
2/3
album genre
2010
compilation:Yes
gapless:No
:
title1
artist1
:
title2
artist2

# applescript references
http://dougscripts.com/itunes/itinfo/cdsysprefs.php
http://www.dougscripts.com/itunes/itinfo/info02.php
