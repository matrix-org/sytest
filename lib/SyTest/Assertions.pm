package SyTest::Assertions;

use strict;
use warnings;

use Carp;

use JSON;

use Exporter 'import';
our @EXPORT_OK = qw(
   assert_ok
   assert_eq

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

use Data::Dump 'pp';

our %EXPORT_TAGS = (
   all => \@EXPORT_OK,
);

=head2 assert_ok

   assert_ok( $ok, $name )

Fails the test if C<$ok> is false.

=cut

sub assert_ok
{
   my ( $ok, $name ) = @_;
   $ok or
      croak "Failed $name";
}

=head2 assert_eq

   assert_eq( $got, $want, $name )

Fails the test of C<$got> is not stringily equal to C<$want>.

=cut

sub assert_eq
{
   my ( $got, $want, $name ) = @_;

   defined $got && defined $want && $got eq $want or
      croak "Got ${\ pp $got }, expected ${\ pp $want } for $name";
}

=head2 assert_json_object

   assert_json_object( $obj )

Fails the test if C<$obj> does not represent a JSON object (i.e. is anything
other than a plain HASH reference).

=cut

sub assert_json_object
{
   my ( $obj ) = @_;
   ref $obj eq "HASH" or croak "Expected a JSON object";
}

=head2 assert_json_keys

   assert_json_keys( $obj, @keys )

Fails the test if C<$obj> does not represent a JSON object, or lacks at least
one of the named keys.

=cut

sub assert_json_keys
{
   my ( $obj, @keys ) = @_;
   assert_json_object( $obj );
   foreach ( @keys ) {
      defined $obj->{$_} or croak "Expected a '$_' key";
   }
}

=head2 assert_json_list

   assert_json_list( $list )

Fails the test if C<$list> does not represent a JSON list (i.e. is anything
other than a plain ARRAY reference).

=cut

sub assert_json_list
{
   my ( $list ) = @_;
   ref $list eq "ARRAY" or croak "Expected a JSON list";
}

=head2 assert_json_nonempty_list

   assert_json_nonempty_list( $list )

Fails the test if C<$list> does not represent a JSON list, or is empty.

=cut

sub assert_json_nonempty_list
{
   my ( $list ) = @_;
   assert_json_list( $list );
   @$list or croak "Expected a non-empty JSON list";
}

=head2 assert_json_number

   assert_json_number( $num )

Fails the test if C<$num> does not represent a JSON number (i.e. is anything
other than an instance of C<JSON::number>).

=cut

sub assert_json_number
{
   my ( $num ) = @_;
   # Our hacked-up JSON decoder represents numbers as JSON::number instances
   ref $num eq "JSON::number" or croak "Expected a JSON number";
}

=head2 assert_json_string

   assert_json_string( $str )

Fails the test if C<$str> does not represent a JSON string (i.e. is some kind
of referential scalar).

=cut

sub assert_json_string
{
   my ( $str ) = @_;
   !ref $str or croak "Expected a JSON string";
}

=head2 assert_json_nonempty_string

   assert_json_nonempty_string( $str )

Fails the test if C<$str> does not represent a JSON string, or is empty.

=cut

sub assert_json_nonempty_string
{
   my ( $str ) = @_;
   !ref $str and length $str or croak "Expected a non-empty JSON string";
}

use constant JSON_BOOLEAN_CLASS => ref( JSON::true );

=head2 assert_json_boolean

   assert_json_boolean( $bool )

Fails the test if C<$bool> does not represent a JSON boolean (i.e. is anything
other than an instance of the class the JSON parser uses to represent
booleans).

=cut

sub assert_json_boolean
{
   my ( $obj ) = @_;
   ref $obj eq JSON_BOOLEAN_CLASS or croak "Expected a JSON boolean";
}

=head2 assert_base64_unpadded

   assert_base64_unpadded( $str )

Fails the test if C<$str> is not a plain string, contains any characters
invalid in a Base64 encoding, or contains the trailing C<=> padding characters.

=cut

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
