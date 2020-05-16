#!/usr/bin/perl
#
# Catch all CUPS/IPP notifier
#
# Nicola Ruggero 2011 <nicola@nxnt.org>
#
# Based on a IPP perl parser project I don't remember, sorry!
#
# ====================================================================
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ====================================================================

use strict;
use warnings;
use Data::Dumper;
use MIME::Lite::TT;
use Sys::Hostname;

######## Globals and Constants ########
my $local_hostname;
$local_hostname = hostname =~ /\.example\.com$/i ? hostname : hostname . ".example.com";
our $VERSION = "0.1.0";
my $debug = 1;
my $notification_level;
my $email;
my $cmd_argument;

#### CONSTANTS ####

###
# register constants
# (modified standard perl constant.pm without all the checking)
#
sub registerConstants {
	my $tableref = shift;
	my %constants = %{+shift};

    foreach my $name ( keys %constants ) {
        my $pkg = caller;

        no strict 'refs';
        my $full_name = "${pkg}::$name";

        my $scalar = $constants{$name};
        *$full_name = sub () { $scalar };

        $tableref->{$scalar} = $name;
    }
}

# IPP Version
use constant IPP_MAJOR_VERSION => 1;
use constant IPP_MINOR_VERSION => 1;

# IPP Types

our %type;
registerConstants(\%type, {
     DELETE_ATTRIBUTE => 0x16, 
     INTEGER => 0x21,
     BOOLEAN => 0x22,
     ENUM => 0x23,
     OCTET_STRING => 0x30,
     DATE_TIME => 0x31,
     RESOLUTION => 0x32,
     RANGE_OF_INTEGER => 0x33,
     BEG_COLLECTION => 0x34,
     TEXT_WITH_LANGUAGE => 0x35,
     NAME_WITH_LANGUAGE => 0x36,
     END_COLLECTION => 0x37,
     TEXT_WITHOUT_LANGUAGE => 0x41,
     NAME_WITHOUT_LANGUAGE => 0x42,
     KEYWORD => 0x44,
     URI => 0x45,
     URI_SCHEME => 0x46,
     CHARSET => 0x47,
     NATURAL_LANGUAGE => 0x48,
     MIME_MEDIA_TYPE => 0x49,
     MEMBER_ATTR_NAME => 0x4A,
});

# IPP Group tags

our %group;
registerConstants(\%group, {
	OPERATION_ATTRIBUTES => 0x01,
	JOB_ATTRIBUTES => 0x02,
	END_OF_ATTRIBUTES => 0x03,
	PRINTER_ATTRIBUTES => 0x04,
	UNSUPPORTED_ATTRIBUTES => 0x05,
	SUBSCRIPTION_ATTRIBUTES => 0x06,
	EVENT_NOTIFICATION_ATTRIBUTES => 0x07
});

# IPP Operations

our %operation;
registerConstants(\%operation, {
    IPP_PRINT_JOB => 0x0002,
    IPP_PRINT_URI => 0x0003,
    IPP_VALIDATE_JOB => 0x0004,
    IPP_CREATE_JOB => 0x0005,
    IPP_SEND_DOCUMENT => 0x0006,
    IPP_SEND_URI => 0x0007,
    IPP_CANCEL_JOB => 0x0008,
    IPP_GET_JOB_ATTRIBUTES => 0x0009,
    IPP_GET_JOBS => 0x000a,
    IPP_GET_PRINTER_ATTRIBUTES => 0x000b,
    IPP_HOLD_JOB => 0x000c,
    IPP_RELEASE_JOB => 0x000d,
    IPP_RESTART_JOB => 0x000e,

    IPP_PAUSE_PRINTER => 0x0010,
    IPP_RESUME_PRINTER => 0x0011,
    IPP_PURGE_JOBS => 0x0012,
    IPP_SET_PRINTER_ATTRIBUTES => 0x0013,
    IPP_SET_JOB_ATTRIBUTES => 0x0014,
    IPP_GET_PRINTER_SUPPORTED_VALUES => 0x0015,
    IPP_CREATE_PRINTER_SUBSCRIPTION => 0x0016,
    IPP_CREATE_JOB_SUBSCRIPTION => 0x0017,
    IPP_GET_SUBSCRIPTION_ATTRIBUTES => 0x0018,
    IPP_GET_SUBSCRIPTIONS => 0x0019,
    IPP_RENEW_SUBSCRIPTION => 0x001a,
    IPP_CANCEL_SUBSCRIPTION => 0x001b,
    IPP_GET_NOTIFICATIONS => 0x001c,
    IPP_SEND_NOTIFICATIONS => 0x001d,

    IPP_GET_PRINT_SUPPORT_FILES => 0x0021,
    IPP_ENABLE_PRINTER => 0x0022,
    IPP_DISABLE_PRINTER => 0x0023,
    IPP_PAUSE_PRINTER_AFTER_CURRENT_JOB => 0x0024,
    IPP_HOLD_NEW_JOBS => 0x0025,
    IPP_RELEASE_HELD_NEW_JOBS => 0x0026,
    IPP_DEACTIVATE_PRINTER => 0x0027,
    IPP_ACTIVATE_PRINTER => 0x0028,
    IPP_RESTART_PRINTER => 0x0029,
    IPP_SHUTDOWN_PRINTER => 0x002a,
    IPP_STARTUP_PRINTER => 0x002b,
    IPP_REPROCESS_JOB => 0x002c,
    IPP_CANCEL_CURRENT_JOB => 0x002d,
    IPP_SUSPEND_CURRENT_JOB => 0x002e,
    IPP_RESUME_JOB => 0x002f,
    IPP_PROMOTE_JOB => 0x0030,
    IPP_SCHEDULE_JOB_AFTER => 0x0031,

    # IPP private Operations start at 0x4000
    CUPS_GET_DEFAULT => 0x4001,
    CUPS_GET_PRINTERS => 0x4002,
    CUPS_ADD_PRINTER => 0x4003,
    CUPS_DELETE_PRINTER => 0x4004,
    CUPS_GET_CLASSES => 0x4005,
    CUPS_ADD_CLASS => 0x4006,
    CUPS_DELETE_CLASS => 0x4007,
    CUPS_ACCEPT_JOBS => 0x4008,
    CUPS_REJECT_JOBS => 0x4009,
    CUPS_SET_DEFAULT => 0x400a,
    CUPS_GET_DEVICES => 0x400b,
    CUPS_GET_PPDS => 0x400c,
    CUPS_MOVE_JOB => 0x400d,
    CUPS_ADD_DEVICE => 0x400e,
    CUPS_DELETE_DEVICE => 0x400f,
});

# Finishings

our %finishing;
registerConstants(\%finishing, {
  FINISHINGS_NONE => 3,
  FINISHINGS_STAPLE => 4,
  FINISHINGS_PUNCH => 5,
  FINISHINGS_COVER => 6,
  FINISHINGS_BIND => 7,
  FINISHINGS_SADDLE_STITCH => 8,
  FINISHINGS_EDGE_STITCH => 9,
  FINISHINGS_FOLD => 10,
  FINISHINGS_TRIM => 11,
  FINISHINGS_BALE => 12,
  FINISHINGS_BOOKLET_MAKER => 13,
  FINISHINGS_JOB_OFFSET => 14,
  FINISHINGS_STAPLE_TOP_LEFT => 20,
  FINISHINGS_STAPLE_BOTTOM_LEFT => 21,
  FINISHINGS_STAPLE_TOP_RIGHT => 22,
  FINISHINGS_STAPLE_BOTTOM_RIGHT => 23,
  FINISHINGS_EDGE_STITCH_LEFT => 24,
  FINISHINGS_EDGE_STITCH_TOP => 25,
  FINISHINGS_EDGE_STITCH_RIGHT => 26,
  FINISHINGS_EDGE_STITCH_BOTTOM => 27,
  FINISHINGS_STAPLE_DUAL_LEFT => 28,
  FINISHINGS_STAPLE_DUAL_TOP => 29,
  FINISHINGS_STAPLE_DUAL_RIGHT => 30,
  FINISHINGS_STAPLE_DUAL_BOTTOM => 31,
  FINISHINGS_BIND_LEFT => 50,
  FINISHINGS_BIND_TOP => 51,
  FINISHINGS_BIND_RIGHT => 52,
  FINISHINGS_BIND_BOTTOM => 53,
});

# IPP Printer state

our %printerState;
registerConstants(\%printerState, {
    STATE_IDLE=>3,
    STATE_PROCESSING => 4,
    STATE_STOPPED => 5,
});

# Job state

our %jobState;
registerConstants(\%jobState, {
    JOBSTATE_PENDING => 3,
    JOBSTATE_PENDING_HELD => 4,
    JOBSTATE_PROCESSING => 5,
    JOBSTATE_PROCESSING_STOPPED => 6,
    JOBSTATE_CANCELED => 7,
    JOBSTATE_ABORTED => 8,
    JOBSTATE_COMPLETED => 9,
});

# Orientations

our %orientation;
registerConstants(\%orientation, {
	ORIENTATION_PORTRAIT => 3,          # no rotation
	ORIENTATION_LANDSCAPE => 4,         # 90 degrees counter-clockwise
	ORIENTATION_REVERSE_LANDSCAPE => 5, # 90 degrees clockwise
	ORIENTATION_REVERSE_PORTRAIT => 6,  # 180 degrees
});

our %statusCodes = (
                 0x0000 => "successful-ok",
                 0x0001 => "successful-ok-ignored-or-substituted-attributes",
                 0x0002 => "successful-ok-conflicting-attributes",
                 0x0003 => "successful-ok-ignored-subscriptions",
                 0x0004 => "successful-ok-ignored-notifications",
                 0x0005 => "successful-ok-too-many-events",
                 0x0006 => "successful-ok-but-cancel-subscription",
		    # Client errors
                 0x0400 => "client-error-bad-request",
                 0x0401 => "client-error-forbidden",
                 0x0402 => "client-error-not-authenticated",
                 0x0403 => "client-error-not-authorized",
                 0x0404 => "client-error-not-possible",
                 0x0405 => "client-error-timeout",
                 0x0406 => "client-error-not-found",
                 0x0407 => "client-error-gone",
                 0x0408 => "client-error-request-entity-too-large",
                 0x0409 => "client-error-request-value-too-long",
                 0x040a => "client-error-document-format-not-supported",
                 0x040b => "client-error-attributes-or-values-not-supported",
                 0x040c => "client-error-uri-scheme-not-supported",
                 0x040d => "client-error-charset-not-supported",
                 0x040e => "client-error-conflicting-attributes",
                 0x040f => "client-error-compression-not-supported",
                 0x0410 => "client-error-compression-error",
                 0x0411 => "client-error-document-format-error",
                 0x0412 => "client-error-document-access-error",
                 0x0413 => "client-error-attributes-not-settable",
                 0x0414 => "client-error-ignored-all-subscriptions",
                 0x0415 => "client-error-too-many-subscriptions",
                 0x0416 => "client-error-ignored-all-notifications",
                 0x0417 => "client-error-print-support-file-not-found",
		    #Server errors
                 0x0500 => "server-error-internal-error",
                 0x0501 => "server-error-operation-not-supported",
                 0x0502 => "server-error-service-unavailable",
                 0x0503 => "server-error-version-not-supported",
                 0x0504 => "server-error-device-error",
                 0x0505 => "server-error-temporary-error",
                 0x0506 => "server-error-not-accepting-jobs",
                 0x0507 => "server-error-busy",
                 0x0508 => "server-error-job-canceled",
                 0x0509 => "server-error-multiple-document-jobs-not-supported",
                 0x050a => "server-error-printer-is-deactivated"
);

# Parse command line
if (@ARGV > 0 )
  {
	$cmd_argument = $ARGV[0] or usage();
	$cmd_argument =~ /cupsmail:\/\/(\w{3}):(.*\@.*)/;
	$notification_level = $1;
	$email = $2;
  }
else 
  {
    usage();
  }

usage() if ($email !~ /\@/);
usage() if ($notification_level !~ /(?:err|all)/);

print "Starting Cupsmail notification service $VERSION on $local_hostname\n" if ($debug);
print "Command line dump: " . join (' ', @ARGV) . "\n" if ($debug);

# Initialize IPP response structure
my $response = {
	HTTP_CODE => '200',
	HTTP_MESSAGE => 'OK',
};

# Read IPP bytes from STDIN
my $bytes;
print "Reading raw IPP data from stdin...\n" if ($debug);
while (<STDIN>)
	{
		$bytes = $_;
	}

# Decode IPP bytes and convert to perl structure
print hexdump($bytes) if ($debug);
decodeIPPHeader($bytes, $response);
decodeIPPGroups($bytes, $response);
print "IPP Perl Structure Dump:\n" if ($debug);
print Dumper($response) if ($debug);

if ($response->{GROUPS}[0]{'job-state'} == 0x9)
  {
	if ($notification_level =~ /all/)
	  {
		do_send_mail("ok", $email) == 0 or warn("Unable to send mail\n");
	  }
  }
else
  {
	do_send_mail("ko", $email) == 0 or warn("Unable to send mail\n");
  }

exit 0;

######## Functions ########

sub usage {
    die "Usage: $0  [all|err]:username\@domain.com notify-user-data\n"
}

sub decodeIPPHeader {
	my $bytes = shift;
	my $response = shift;
	
	my $data;
	{use bytes; $data = substr($bytes,0,8);}
	
	my ($majorVersion, $minorVersion, $status, $requestId) = unpack("CCnN", $data);
	
	$response->{VERSION} = $majorVersion . "." . $minorVersion;
	
	$response->{STATUS} = $status;
	
	$response->{REQUEST_ID} = $requestId;
}

sub decodeIPPGroups {
	my $bytes = shift;
	my $response = shift;
	
	$response->{GROUPS} = [];
		
	# begin directly after IPPHeader (length 8 byte)
	my $offset = 8;
	my $currentGroup = "";
	my $type;
	
	do {
		{
		use bytes;
			die ("Expected Group Tag at begin of IPP response. Not enough bytes.\n") if (length($bytes) < $offset);
			$type = ord(substr($bytes, $offset, 1));
		}
		
		$offset++;
				
		if (exists($group{$type})) {
			print "group $type found\n" if ($debug);
			if ($currentGroup) {
				push @{$response->{GROUPS}}, $currentGroup;
			}
			
			if ($type != &END_OF_ATTRIBUTES) {
				$currentGroup = {
					TYPE => $type
				};
			}
		} elsif ($currentGroup eq "") {
			die ("Expected Group Tag at begin of IPP response.\n");
		} else {
			decodeAttribute($bytes, \$offset, $type, $currentGroup);
		}	
	} while ($type != &END_OF_ATTRIBUTES);
}

sub hexdump {
	use bytes;
	
	my $bytes = shift;
    my @bytes = unpack("c*", $bytes);

    my $width = 16; #how many bytes to print per line
    my $hexWidth = 3*$width;

	my $string = "";

    my $offset = 0;

    while ($offset *$width < length($bytes)) {
    	my $hexString = "";
    	my $charString = ""; 
    	for (my $i = 0; $i < $width; $i++) {
    		if ($offset*$width + $i < length($bytes)) {
    			my $char;
    			{use bytes;$char = substr($bytes, $offset*$width + $i, 1);}
			
    			$hexString .= sprintf("%02X ", ord($char));
    			if ($char =~ /[\w\-\:]/) {
    				$charString .= $char;
    			} else {
    				$charString .= ".";
    			}
    		}
    	}
	
    	$string .= sprintf("%-${hexWidth}s%s\n",$hexString,$charString);
    	$offset++;
    }
    return $string;
}

my $previousKey; # used for 1setOf values
sub decodeAttribute {
	my $bytes = shift;
	my $offsetref = shift;
	my $type = shift;
	my $group = shift;

	my $data;
	{ use bytes;
	$data = substr($bytes, $$offsetref);
	}
	
	my ($key, $value, $addValue);
	
	testLengths($bytes, $$offsetref);
	
	($key, $value) = unpack("n/a* n/a*", $data);
	
	testKey($key);
	
	{ use bytes;
	$$offsetref += 4 + length($key) + length($value);
	}

	print "decoding attribute \"$key\" => $type{$type}(" . sprintf("%#x", $type) . ")\n" if ($debug);

	$value = transformValue($type, $key, $value);
	 	
	# if key empty, attribute is 1setOf
	if (!$key) {
		if (!ref($group->{$previousKey})) {
			my $arrayref = [$group->{$previousKey}];
			$group->{$previousKey} = $arrayref;
		} 
		push @{$group->{$previousKey}}, $value;
	} else {
		$group->{$key} = $value;
		$previousKey = $key;
	}
}

sub testLengths {
	use bytes;
	
	my $bytes = shift;
	my $offset = shift;

	my $keyLength = unpack("n", substr($bytes, $offset, 2));
	
	if ($offset + 2 + $keyLength > length($bytes)) {
		my $dump = hexdump($bytes);
		print STDERR "---IPP RESPONSE DUMP (current offset: $offset):---\n$dump\n";
		die ("ERROR: IPP response is not RFC conform.\n");
	}
	
	my $valueLength = unpack("n", substr($bytes, $offset + 2 + $keyLength, 2));
	
	if ($offset + 4 + $keyLength + $valueLength > length($bytes)) {
		my $dump = hexdump($bytes);
		print STDERR "---IPP RESPONSE DUMP (current offset: $offset):\n---$dump\n";
		die ("ERROR: IPP response is not RFC conform.");
	}
}

sub testKey {
	my $key = shift;
	if (not $key =~ /^[\w\-]*$/) {
		die ("Probably wrong attribute key: $key\n");
	}
}

sub transformValue {
	my $type = shift;
	my $key = shift;
	my $value = shift;
	
	if ($type == &TEXT_WITHOUT_LANGUAGE 
			|| $type == &NAME_WITHOUT_LANGUAGE) {
				#RFC:  textWithoutLanguage,  LOCALIZED-STRING.
				#RFC:  nameWithoutLanguage
				return $value;
	} elsif ($type == &TEXT_WITH_LANGUAGE 
			|| $type == &NAME_WITH_LANGUAGE) {
				#RFC:  textWithLanguage      OCTET-STRING consisting of 4 fields:
				#RFC:                          a. a SIGNED-SHORT which is the number of
				#RFC:                             octets in the following field
				#RFC:                          b. a value of type natural-language,
				#RFC:                          c. a SIGNED-SHORT which is the number of
				#RFC:                             octets in the following field,
				#RFC:                          d. a value of type textWithoutLanguage.
				#RFC:                        The length of a textWithLanguage value MUST be
				#RFC:                        4 + the value of field a + the value of field c.
				my ($language, $text) = unpack("n/a*n/a*", $value);
				return "$language, $text";
	} elsif ($type == &CHARSET
			|| $type == &NATURAL_LANGUAGE
			|| $type == &MIME_MEDIA_TYPE
			|| $type == &KEYWORD
			|| $type == &URI
			|| $type == &URI_SCHEME) {
				#RFC:  charset,              US-ASCII-STRING.
				#RFC:  naturalLanguage,
				#RFC:  mimeMediaType,
				#RFC:  keyword, uri, and
				#RFC:  uriScheme
				return $value;
	} elsif ($type == &BOOLEAN) {
				#RFC:  boolean               SIGNED-BYTE  where 0x00 is 'false' and 0x01 is
				#RFC:                        'true'.
				return unpack("c", $value);
	} elsif ($type == &INTEGER 
			|| $type == &ENUM) {
				#RFC:  integer and enum      a SIGNED-INTEGER.
				return unpack("N", $value);
	} elsif ($type == &DATE_TIME) {
				#RFC:  dateTime              OCTET-STRING consisting of eleven octets whose
				#RFC:                        contents are defined by "DateAndTime" in RFC
				#RFC:                        1903 [RFC1903].
				my ($year, $month, $day, $hour, $minute, $seconds, $deciSeconds, $direction, $utcHourDiff, $utcMinuteDiff) 
					= unpack("nCCCCCCaCC", $value);
				return "$month-$day-$year,$hour:$minute:$seconds.$deciSeconds,$direction$utcHourDiff:$utcMinuteDiff";
	} elsif ($type == &RESOLUTION) {
				#RFC:  resolution            OCTET-STRING consisting of nine octets of  2
				#RFC:                        SIGNED-INTEGERs followed by a SIGNED-BYTE. The
				#RFC:                        first SIGNED-INTEGER contains the value of
				#RFC:                        cross feed direction resolution. The second
				#RFC:                        SIGNED-INTEGER contains the value of feed
				#RFC:                        direction resolution. The SIGNED-BYTE contains
				#RFC:                        the units				
				#                        unit: 3 = dots per inch
				#                              4 = dots per cm
				my ($crossFeedResolution, $feedResolution, $unit)  = unpack("NNc", $value);
				my $unitText;
				if ($unit == 3) {
					$unitText = "dpi";
				} elsif ($unit == 4) {
					$unitText = "dpc";
				} else {
					die ("Unknown Unit value: $unit\n");
					$unitText = $unit;
				}
				return "$crossFeedResolution, $feedResolution $unitText";
	} elsif ($type == &RANGE_OF_INTEGER) {
				#RFC:  rangeOfInteger        Eight octets consisting of 2 SIGNED-INTEGERs.
				#RFC:                        The first SIGNED-INTEGER contains the lower
				#RFC:                        bound and the second SIGNED-INTEGER contains
				#RFC:                        the upper bound.
				my ($lowerBound, $upperBound) = unpack("NN", $value);
				return "$lowerBound:$upperBound";
	} elsif ($type == &OCTET_STRING) {
				#RFC:  octetString           OCTET-STRING
				return $value;
	} elsif ($type == &BEG_COLLECTION) {
		if ($key) {
			die "WARNING: Collection Syntax not supported. Attribute \"$key\" will have invalid value.\n";
		}
	} elsif ($type == &END_COLLECTION
	      || $type == &MEMBER_ATTR_NAME) {
		return $value;
	} else {
		die "Unknown Value type ", sprintf("%#lx",$type) , " for key \"$key\". Performing no transformation.\n";
		return $value;
	}
}

sub do_send_mail {

    my $email_type = shift;
    my $dest_email = shift;
    my $template;
    my $subject;
    my $sysadmin_cc;

    if ($email_type =~ /ok/i)
      {
	    $subject = '[OK] Printing job completed';
	    $sysadmin_cc = '';
	    $template = <<TEMPLATE;

Print job successfully completed by your printer.

-- Details --------------------------------------------------------
job-id            : [% job_id %]
printer-name      : [% printer_name %]
job-name          : [% job_name %]
job-state         : [% job_state %]
job-state-reasons : [% job_state_reasons %]

TEMPLATE
      }
    else
      {
      	    $subject = '[WARN] Printing service alert';
	    $sysadmin_cc = 'print_admins@example.com';
	    $template = <<TEMPLATE;

Error printing the following job.
Please recover such job or contact your system administrator.

-- Details --------------------------------------------------------
job-id            : [% job_id %]
printer-name      : [% printer_name %]
job-name          : [% job_name %]
job-state         : [% job_state %]
job-state-reasons : [% job_state_reasons %]

TEMPLATE
      }

    my %params = (
		job_id => $response->{GROUPS}[0]{'notify-job-id'}, 
		printer_name => $response->{GROUPS}[0]{'printer-name'},
		job_name => $response->{GROUPS}[0]{'job-name'},
		job_state => $jobState{$response->{GROUPS}[0]{'job-state'}} . sprintf(" (%#x)", $response->{GROUPS}[0]{'job-state'}),
		job_state_reasons => $response->{GROUPS}[0]{'job-state-reasons'});
    my %options = (EVAL_PERL=>1);

    my $msg = MIME::Lite::TT->new(
		From => 'Batch Printing Service <root@' . $local_hostname . '>',
		To => $dest_email,
		Cc => $sysadmin_cc,
		Subject => $subject,
		Template => \$template,
		TmplParams => \%params,
		TmplOptions => \%options,
	    );

    print "Sending notification mail to: $dest_email - type: \"$email_type\"\n" if ($debug);
    $msg->send() || return 1;
    return 0;

}
