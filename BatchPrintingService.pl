#!/usr/bin/perl

# Batch Printing Service
# Copyright (c) 2009-2011 Nicola Ruggero <nicola@nxnt.org>
#
# This application polls some folders looking for xml files, that
# will be analyzed looking for files to print.
# Xml files contain some printing options and a file list as well.
#
# Usage: BatchPrintingService.pl [<polling_folder>]
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
use Cwd qw(abs_path);

use Proc::PID::File;
use Proc::Daemon;

use XML::Smart;
use File::Find;
use MIME::Lite::TT;
use IO::CaptureOutput qw(capture_exec_combined);
use Log::Log4perl qw(get_logger);
use Sys::Hostname;

our $VERSION = "1.0.6";
my $local_hostname;
$local_hostname = hostname =~ /\.example\.com$/i ? hostname : hostname . ".example.com";


###############################################################################
# Initialize log engine for the parent

initialize_log() or die "Unable to initialize log: $!\n";
my $logger = Log::Log4perl->get_logger();


###############################################################################
# Initialize application

$logger->info("Starting Batch Printing Service $VERSION on $local_hostname");
$logger->info('Copyright (c) 2009-2011 Nicola Ruggero <nicola@nxnt.org>');

@ARGV = qw(/apps/cups/data) unless @ARGV;
my @polling_dirs;

foreach my $polling_dir (@ARGV) {
	$polling_dir = abs_path($polling_dir) or $logger->logdie("Unable to poll folder(s) specified");
	push (@polling_dirs, $polling_dir);
}

my $polling_dirs_view = join(" ", @polling_dirs);
$logger->info("Polling folders: ", $polling_dirs_view);

# Globals
my $printer_name;
my $notification_email;
my $notify_only_errors;
my $cups_notifier;
my $file_static_pattern;
my $file_static_copies;
my $xml_filename;
my %printing_filename_status;
my %printing_filename_status_for_renaming;
my @files_to_print;
my $file_to_print;


###############################################################################
# Initialize process handling

# Fork to background (daemonize)
start_daemon();
$logger->debug("Forked to background (pid=", $$, ")");

# Setup signal handlers so we can shutdown gracefully
my $keep_running = 1;
$SIG{HUP}  = sub { $logger->warn("Caught SIGHUP:  exiting gracefully"); $keep_running = 0; };
$SIG{INT}  = sub { $logger->warn("Caught SIGINT:  exiting gracefully"); $keep_running = 0; };
$SIG{QUIT} = sub { $logger->warn("Caught SIGQUIT:  exiting gracefully"); $keep_running = 0; };
$SIG{TERM} = sub { $logger->warn("Caught SIGTERM:  exiting gracefully"); $keep_running = 0; };


###############################################################################
# Main application loop

while ($keep_running) {

    $logger->debug("Main loop checkpoint: ", time());

    # Find all xml files in @polling_dirs path
    find (\&parse_xml, @polling_dirs);
    sleep(60);

}


###############################################################################
# Shutdown application

$logger->debug("Shutting down up main loop");
$logger->info("Shutdown complete");


###############################################################################
# Functions

# Load default log configuration and initialize it
sub initialize_log {

    # Define configuration
    my $log_cfg = qq(
	    log4perl.logger                     = INFO, Log2File
	    log4perl.appender.Log2File          = Log::Log4perl::Appender::File
	    log4perl.appender.Log2File.filename = /apps/cups/log/BatchPrintingService/BatchPrintingService.log
	    log4perl.appender.Log2File.mode     = append
	    log4perl.appender.Log2File.layout   = PatternLayout
	    log4perl.appender.Log2File.layout.ConversionPattern = %d [%M] %-5p - %m%n
	);

    # Initialize logging behaviour
    Log::Log4perl->init( \$log_cfg );

}

# Fork and detach from the parent process
sub start_daemon {

    # Get log context
    $logger = Log::Log4perl->get_logger();

    # Do actual fork()
    $logger->debug("Forking to background");
    eval { Proc::Daemon::Init; };
    if ($@) {
	die_daemon("Unable to start daemon:  $@");
    }

    # Re-initialize log engine for the children (daemon)
    initialize_log() or die "Unable to initialize log: $!\n";
    $logger = Log::Log4perl->get_logger();

    # Check if is already running
    die_daemon("Daemon is already running!") if Proc::PID::File->running(dir => '/var/run');

}

# Write die messages to the log before shutting down
sub die_daemon {

    # Get log context
    $logger = Log::Log4perl->get_logger();

    $logger->fatal("$_[0] dying instance...");
    die $_[0];

}

sub parse_xml {

    # Filter out trivial files
    return unless -f and $_ =~ /\.xml$/i;

    # Get log context
    $logger = Log::Log4perl->get_logger();

    # Create the object and load the file:
    $logger->debug("Parsing XML: $File::Find::name");
    $xml_filename = $_;
    my $xml_obj = XML::Smart->new($xml_filename) || $logger->warn("Unable to create XMl object from: ", $xml_filename) && return;

    # Change the root and get some general informations:
    $xml_obj = $xml_obj->{BatchPrintingService} || $logger->warn("Unable to chroot XMl object in: ", $xml_filename) && return;
    $logger->debug("Getting general informations...");

    $notification_email = $xml_obj->{NotificationEmail};
    $notify_only_errors = $xml_obj->{NotificationEmail}{only_errors} or $notify_only_errors = 0;
    $logger->debug("NotificationEmail: $notification_email - only_errors = $notify_only_errors");

    if ( $xml_obj->{PrinterName} )
      {
	$printer_name = $xml_obj->{PrinterName};
	$logger->debug("PrinterName: $printer_name");
      }
    else
      {
	$logger->error("Unable to get PrinterName");
	do_send_mail("ko", $xml_filename, $notification_email, "Unable to get PrinterName") == 0 or $logger->error("Unable to send mail");
	# Rename bad XML file
	execute_child ("mv", '-f', $xml_filename, $xml_filename . "_bad");
	return;
      }

    my $collate_copies;
    $collate_copies = $xml_obj->{CollateCopies}{copies} or $collate_copies = 0;
    $logger->debug("CollateCopies: $collate_copies") ;

    my $xml_rename_flag = 0;				# Flag for renaming correctly processed XML files (>0 = Rename <name>_bad)

    # Get file list and process it
    $logger->debug("Checking file list...");
    if ( $xml_obj->{FileList}{File}->is_node() )	# XML contains <File> tags
      {

	# Populate an array of all the objects containing filename and copies to print:
	@files_to_print = @{$xml_obj->{FileList}{File}};
	
	$logger->info("Printing ", scalar(@files_to_print), " file(s) from: ", $xml_filename);

	# Handle collate copies
	my $cycle_collate_copies = 1;
	$cycle_collate_copies = $collate_copies unless ($collate_copies == 0);

	for (my $i = 1; $i <= $cycle_collate_copies; $i++) {
	    foreach $file_to_print (@files_to_print) {

		    my $file_to_print_copies;

		    # Collate copies overrides copies
		    if ( $collate_copies == 0 )
			{
			    $file_to_print_copies = $file_to_print->{Copies} or $file_to_print_copies = 1;
			}
		    else
			{
			    $file_to_print_copies = 1;
			}

    		    unless (-f $file_to_print->{Name}) {
			$logger->warn("File not found for printing, skipped: ", $file_to_print->{Name});
			++$printing_filename_status{$file_to_print->{Name}};
			$printing_filename_status{$file_to_print->{Name}} = sprintf('%-13s %s - %s', '[ NOT FOUND ]', $file_to_print->{Name}, 'File not found for printing, skipped.');
			$xml_rename_flag += 1;		# Rename XML -> <name>_bad
			next;
		    }

		    # Launch print command
		    my @print_args;
			$cups_notifier = ($notify_only_errors == 1) ? 'cupsmail://err:' : 'cupsmail://all:';
		    if ($notification_email =~ /\@/)
		      {
			@print_args = ("lp", '-d', $printer_name, '-o', "notify-recipient-uri=$cups_notifier" . $notification_email, '-o', "copies=$file_to_print_copies", '-o Collate=True', '-o fit-to-page', $file_to_print->{Name});
		      }
			else
			  {
		    @print_args = ("lp", '-d', $printer_name, '-o', "copies=$file_to_print_copies", '-o Collate=True', '-o fit-to-page', $file_to_print->{Name});
			  }

		    my @ren_args;
		    unless ( execute_child (@print_args) )
			{
			    # Rename files if print command has runned correctly
			    @ren_args = ("mv", '-f', $file_to_print->{Name}, $file_to_print->{Name} . "_");
			    $printing_filename_status_for_renaming{$file_to_print->{Name}} = [ @ren_args ];
			}
		    else
			{
			    # Rename files if print command has runned wrongly
			    @ren_args = ("mv", '-f', $file_to_print->{Name}, $file_to_print->{Name} . "_bad");
			    $printing_filename_status_for_renaming{$file_to_print->{Name}} = [ @ren_args ];
			    $xml_rename_flag += 1;	# Rename XML -> <name>_bad
			}

	    }
	}

	# Rename processed files
	foreach (keys %printing_filename_status_for_renaming) {
	    execute_child (@{ $printing_filename_status_for_renaming{$_} });
	}

	# Cleanup hash
	%printing_filename_status_for_renaming = ();
	
      }
    else					# XML does NOT contains <File> tags
      {

	# File list does not exist, get the static filepattern instead
	$logger->debug("FileList tag not found, using StaticPattern");

	if ( $xml_obj->{FileList}{StaticPattern} )
	  {
	    $file_static_pattern = $xml_obj->{FileList}{StaticPattern};
	    $logger->debug("StaticPattern: $file_static_pattern");
	  }
	else
	  {
	    $logger->error("Unable to get StaticPattern");
	    do_send_mail("ko", $xml_filename, $notification_email, "Unable to get StaticPattern") == 0 or $logger->error("Unable to send mail");
	    # Rename bad XML file
	    execute_child ("mv", '-f', $xml_filename, $xml_filename . "_bad");
	    return;
	  }

	$file_static_copies = $xml_obj->{FileList}{StaticCopies} or $file_static_copies = 1;
	$logger->debug("StaticCopies: $file_static_copies");

	# Generate file list from static pattern
	@files_to_print = ();		# Empty array
	find (\&print_static_files, $File::Find::dir);

	$logger->info("Printing ", scalar(@files_to_print), " file(s) from: ", $xml_filename) if (scalar(@files_to_print) > 0);
	
	foreach $file_to_print (@files_to_print) {

	    # Launch print command
	    my @print_args;
	    $cups_notifier = ($notify_only_errors == 1) ? 'cupsmail://err:' : 'cupsmail://all:';
		if ($notification_email =~ /\@/)
		  {
	    @print_args = ("lp", '-d', $printer_name, '-o', "notify-recipient-uri=$cups_notifier" . $notification_email, '-o', "copies=$file_static_copies", '-o Collate=True', '-o fit-to-page', $file_to_print);
		  }
		else
		  {
	    @print_args = ("lp", '-d', $printer_name, '-o', "copies=$file_static_copies", '-o Collate=True', '-o fit-to-page', $file_to_print);
		  }

	    my @ren_args;
	    unless ( execute_child (@print_args) )
	      {
		# Rename files if print command has runned correctly
		@ren_args = ("mv", '-f', $file_to_print, $file_to_print . "_");
		execute_child (@ren_args);
	      }
	    else
	      {
		# Rename files if print command has runned wrongly
		@ren_args = ("mv", '-f', $file_to_print, $file_to_print . "_bad");
		execute_child (@ren_args);
	      }

	}
	
	$xml_rename_flag = -1;
      }

    # Rename xml file if *ALL* print command has runned correctly, else rename _bad
    my @renxml_args;
    if ($xml_rename_flag == 0)
      {
	@renxml_args = ("mv", '-f', $xml_filename, $xml_filename . "_");
      }
    else
      {
	@renxml_args = ("mv", '-f', $xml_filename, $xml_filename . "_bad");
      }

    execute_child (@renxml_args) if ($xml_rename_flag != -1);	# Skip renaming for XML static

    # Send notification email and empty notification messages hash.
    return unless (keys %printing_filename_status);
    $logger->debug("Preparing notification mail...");

    my @email_messages = values %printing_filename_status;
    $logger->debug("Counting ", scalar(@email_messages), " message(s) of which ", scalar (grep { /OK/ } values %printing_filename_status), " are OK.");

    if ( scalar(grep { /OK/ } values %printing_filename_status) == scalar(@email_messages) )
      {
	do_send_mail ("ok", $xml_filename, $notification_email, join("\n", @email_messages)) if ($notify_only_errors == 0);
      }
    else
      {
	do_send_mail ("ko", $xml_filename, $notification_email, join("\n", @email_messages));
      }

    # Cleanup hash
    %printing_filename_status = ();

}

sub print_static_files {

    # Filter out trivial files
    return unless -f and $_ =~ /^$file_static_pattern$/i;

    # Get log context
    $logger = Log::Log4perl->get_logger();

    push (@files_to_print, $_);

}

sub execute_child {

    # Get log context
    $logger = Log::Log4perl->get_logger();

    $logger->debug("Executing child: ", join(" ", @_));

    my $combined_output;
    my $success;
    my $exit_code;
    my $printing_filename = $_[$#_];

    ($combined_output, $success, $exit_code) = capture_exec_combined(@_);

    $exit_code = $exit_code >> 8;

    if ($? & 127)
      {
	$logger->warn("Child died with signal: ", $? & 127);
	return 1;
      }
    elsif ($? & 128)
      {
	$logger->warn("Child died with signal: ", $? & 128, "(core dump)");
	return 1;
      }
    elsif ($exit_code == 0)
      {
	$logger->debug("Child exited with value: OK (RC=0)");
	if ($_[0] =~ m/^lp/)
	  {
	    ++$printing_filename_status{$printing_filename};
	    $printing_filename_status{$printing_filename} = sprintf('%-13s %s - %s - %s', '[ OK ]', $printing_filename, $combined_output, "RC=$exit_code");
	  }
	return 0;
      }
    else
      {
	$logger->warn("Child exited with value: KO (RC=$exit_code)");
	$logger->warn("Error messages:", $combined_output);
	if ($_[0] =~ m/^lp/)
	  {
	    ++$printing_filename_status{$printing_filename};
	    $printing_filename_status{$printing_filename} = sprintf('%-13s %s - %s - %s', '[ ERR ]', $printing_filename, $combined_output, "RC=$exit_code");
	  }
	return 1;
      }

}

sub do_send_mail {

    # Get log context
    $logger = Log::Log4perl->get_logger();

    my $email_type = shift;
    my $xml_filename = shift;
    my $dest_email = shift;
    my $template;
    my $subject;
    my $sysadmin_cc;

    if ($email_type =~ /ok/i)
      {
	    $subject = '[OK] Printing job submitted';
	    $sysadmin_cc = '';
	    $template = <<TEMPLATE;

Print job successfully submitted to your printer.

XML master file: [% xml_filename %]

-- Details --------------------------------------------------------
[% messages %]

TEMPLATE
      }
    else
      {
      	    $subject = '[WARN] Printing service alert';
	    $sysadmin_cc = 'print_admins@example.com';
	    $template = <<TEMPLATE;

Error while executing some child processes.

Guru meditation at [% who %] line [% line %] pid [% pid %] ([% crashtime %])
Please contact your system administrator.

XML master file: [% xml_filename %]

-- Details --------------------------------------------------------
[% messages %]

TEMPLATE
      }

    my %params = (
		who => (caller(1))[3], 
		line => (caller(1))[2],
		pid => $$, 
		crashtime => time(),
		xml_filename => $xml_filename,
		messages => @_);
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

    $logger->info("Sending notification mail to: $dest_email - type: \"$email_type\"");
    $msg->send() || return 1;
    return 0;

}
