package SyTest::Assertions;

use strict;
use warnings;

use Carp;

use JSON;

use Exporter 'import';
our @EXPORT_OK = qw(
   assert_ok
   assert_eq
   assert_deeply_eq

   assert_json_object
   assert_json_keys
   assert_json_list
   assert_json_empty_list
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

Fails the test if C<$got> is not stringily equal to C<$want>.

=cut

sub assert_eq
{
   my ( $got, $want, $name ) = @_;

   defined $got && defined $want && $got eq $want or
      croak "Got ${\ pp $got }, expected ${\ pp $want } for $name";
}

=head2 assert_deeply_eq

   assert_deeply_eq( $got, $want, $name )

Fails the test if the data structure in C<$got> is not identical to C<$want>
or if any of the leaves differ in string value.

Structures are identical if they are equal-sized arrays containing
corresponding structurally-equal elements, or if they are hashes containing the
same keys that map to corresponding structurally-equal values.

=cut

sub _assert_deeply_eq
{
   my ( $got, $want, $outerkey, $name ) = @_;
   my $outerkeystr = $outerkey // "(toplevel)";
   $outerkey //= "";

   my $wanttype = ref $want;
   if( !defined $want ) {
      # want undef
      !defined $got or
         croak "Got ${\ pp $got }, expected undef at $outerkeystr for $name";
   }
   elsif( !$wanttype ) {
      # want a non-reference
      defined $got && $got eq $want or
         croak "Got ${\ pp $got }, expected ${\ pp $want } at $outerkeystr for $name";
   }
   # want a reference
   elsif( $wanttype ne ref $got ) {
      croak "Got ${\ pp $got }, expected ${\pp $want } at $outerkeystr for $name";
   }
   elsif( $wanttype eq "ARRAY" ) {
      foreach my $idx ( 0 .. $#$want ) {
         @$got >= $idx or
            croak "Got no value at index $idx at $outerkeystr for $name";
         _assert_deeply_eq( $got->[$idx], $want->[$idx], "$outerkey\[$idx]", $name );
      }
      @$got == @$want or
         croak "Got extra values at $outerkeystr for $name";
   }
   elsif( $wanttype eq "HASH" ) {
      foreach my $key ( keys %$want ) {
         exists $got->{$key} or
            croak "Got no value for '$key' at $outerkeystr for $name";
         _assert_deeply_eq( $got->{$key}, $want->{$key}, "$outerkey\{$key}", $name );
      }
      # Now check that $got didn't have extra keys that we didn't want
      foreach my $key ( keys %$got ) {
         exists $want->{$key} or
            croak "Got a value for '$key' that was not expected at $outerkeystr for $name";
      }
   }
   else {
      die "TODO: not sure how to deeply check a $wanttype reference";
   }
}

sub assert_deeply_eq
{
   my ( $got, $want, $name ) = @_;
   _assert_deeply_eq( $got, $want, undef, $name );
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

=head2 assert_json_empty_list

   assert_json_empty_list( $list )

Fails the test if C<$list> does not represent a JSON list, or if it contains
any elements.

=cut

sub assert_json_empty_list
{
   my ( $list ) = @_;
   assert_json_list( $list );
   @$list and
      croak sprintf "Expected an empty JSON list; got %d elements", scalar @$list;
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

Permitted characters are lower- or uppercase US-ASCII letters, digits, or the
symbols C<+> and C</>.

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
