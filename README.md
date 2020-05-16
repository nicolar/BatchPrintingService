# BatchPrintingService

This application polls some folders looking for xml files, that will be analyzed looking for files to print. 
Xml files contain some printing options and a file list as well.

## Usage

```shell
./BatchPrintingService.pl [<polling_folder>]
```

Where ```polling_folder``` is a folder where BatchPrintingService will look for *.xml files.

The application automatically forks to background when executed.

## XML Examples
There 2 types of XML files:
- Standard
- Static

The *Standard* XML file contains a description of exacly which files you want to print and how:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<BatchPrintingService>
	<PrinterName>PRINTER1</PrinterName>
	<NotificationEmail only_errors="1">print_admins@example.com</NotificationEmail>
	<CollateCopies copies="1" />
	<FileList>
		<File>
			<Name>abc.pdf</Name>
			<Copies>2</Copies>
		</File>
		<File>
			<Name>def.pdf</Name>
			<Copies>1</Copies>
		</File>
		<File>
			<Name>ciao.pdf</Name>
		</File>
	</FileList>
</BatchPrintingService>
```

The *Static* XML file contains a more generic description of which files you want to print and how, normally it is used when you don't know exactly the names of the files, but instead you want to specify a pattern (like *.pdf)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<BatchPrintingService>
	<PrinterName>PRINTER1</PrinterName>
	<NotificationEmail>print_admins@example.com</NotificationEmail>
	<CollateCopies copies="1" />
	<FileList>
		<StaticPattern>test*.pdf</StaticPattern>
		<StaticCopies>2</StaticCopies>
	</FileList>
</BatchPrintingService>
```

## Dependencies

BatchPrintingService needs a CUPS/IPP notifier called "cupsmail" to notify via email the printing results. This is provided here as well.