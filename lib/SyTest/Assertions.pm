package SyTest::Assertions;

use strict;
use warnings;

use Carp;

use JSON;

use Exporter 'import';
our @EXPORT_OK = qw(
   assert_json_object
   assert_json_keys
   assert_json_list
   assert_json_nonempty_list
   assert_json_number
   assert_json_string
   assert_json_nonempty_string
   assert_json_boolean

   assert_base64_unpadded
);

our %EXPORT_TAGS = (
   all => \@EXPORT_OK,
);

sub assert_json_object
{
   my ( $obj ) = @_;
   ref $obj eq "HASH" or croak "Expected a JSON object";
}

sub assert_json_keys
{
   my ( $obj, @keys ) = @_;
   assert_json_object( $obj );
   foreach ( @keys ) {
      defined $obj->{$_} or croak "Expected a '$_' key";
   }
}

sub assert_json_list
{
   my ( $list ) = @_;
   ref $list eq "ARRAY" or croak "Expected a JSON list";
}

sub assert_json_nonempty_list
{
   my ( $list ) = @_;
   assert_json_list( $list );
   @$list or croak "Expected a non-empty JSON list";
}

sub assert_json_number
{
   my ( $num ) = @_;
   # Our hacked-up JSON decoder represents numbers as JSON::number instances
   ref $num eq "JSON::number" or croak "Expected a JSON number";
}

sub assert_json_string
{
   my ( $str ) = @_;
   !ref $str or croak "Expected a JSON string";
}

sub assert_json_nonempty_string
{
   my ( $str ) = @_;
   !ref $str and length $str or croak "Expected a non-empty JSON string";
}

use constant JSON_BOOLEAN_CLASS => ref( JSON::true );

sub assert_json_boolean
{
   my ( $obj ) = @_;
   ref $obj eq JSON_BOOLEAN_CLASS or croak "Expected a JSON boolean";
}

sub assert_base64_unpadded
{
   my ( $str ) = @_;
   !ref $str or croak "Expected a plain string";

   $str =~ m([^A-Za-z0-9+/=]) and
      die "String contains invalid base64 characters";
   $str =~ m(=) and
      die "String contains trailing padding";
}

1;
