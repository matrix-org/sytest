package SyTest::Assertions;

use strict;
use warnings;

use Carp;

use JSON;

use Exporter 'import';
our @EXPORT_OK = qw(
   require_json_object
   require_json_keys
   require_json_list
   require_json_nonempty_list
   require_json_number
   require_json_string
   require_json_nonempty_string
   require_json_boolean

   require_base64_unpadded
);

our %EXPORT_TAGS = (
   all => \@EXPORT_OK,
);

sub require_json_object
{
   my ( $obj ) = @_;
   ref $obj eq "HASH" or croak "Expected a JSON object";
}

sub require_json_keys
{
   my ( $obj, @keys ) = @_;
   require_json_object( $obj );
   foreach ( @keys ) {
      defined $obj->{$_} or croak "Expected a '$_' key";
   }
}

sub require_json_list
{
   my ( $list ) = @_;
   ref $list eq "ARRAY" or croak "Expected a JSON list";
}

sub require_json_nonempty_list
{
   my ( $list ) = @_;
   require_json_list( $list );
   @$list or croak "Expected a non-empty JSON list";
}

sub require_json_number
{
   my ( $num ) = @_;
   # Our hacked-up JSON decoder represents numbers as JSON::number instances
   ref $num eq "JSON::number" or croak "Expected a JSON number";
}

sub require_json_string
{
   my ( $str ) = @_;
   !ref $str or croak "Expected a JSON string";
}

sub require_json_nonempty_string
{
   my ( $str ) = @_;
   !ref $str and length $str or croak "Expected a non-empty JSON string";
}

use constant JSON_BOOLEAN_CLASS => ref( JSON::true );

sub require_json_boolean
{
   my ( $obj ) = @_;
   ref $obj eq JSON_BOOLEAN_CLASS or croak "Expected a JSON boolean";
}

sub require_base64_unpadded
{
   my ( $str ) = @_;
   !ref $str or croak "Expected a plain string";

   $str =~ m([^A-Za-z0-9+/=]) and
      die "String contains invalid base64 characters";
   $str =~ m(=) and
      die "String contains trailing padding";
}

1;
