# -*- coding: utf-8 -*-
# Copyright 2019 The Matrix.org Foundation C.I.C.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package SyTest::SSL;

use Exporter 'import';
our @EXPORT_OK = qw(
   ensure_ssl_key
   create_ssl_cert
);

=head2 ensure_ssl_key

    ensure_ssl_key( $key_file );

Create an SSL key file, if it doesn't exist.

=cut

sub ensure_ssl_key
{
   my ( $key_file ) = @_;

   if ( ! -e $key_file ) {
      # todo: we can do this in pure perl
      system("openssl", "genrsa", "-out", $key_file, "2048") == 0
         or die "openssl genrsa failed $?";
   }
}

=head2 create_ssl_cert

    create_ssl_cert( $cert_file, $key_file, $server_name );

Create a new SSL certificate file. The certificate will be signed by the test CA.

=cut

sub create_ssl_cert
{
   my ( $cert_file, $key_file, $server_name ) = @_;

   # generate a CSR
   my $csr_file = "$cert_file.csr";
   system(
      "openssl", "req", "-new", "-key", $key_file, "-out", $csr_file,
      "-subj", "/CN=$server_name",
   ) == 0 or die "openssl req failed $?";

   # Create extension file
   my $ext_file = "$cert_file.ext";
   open(my $fh, '>', $ext_file) or die "Could not open file '$ext_file': $!";
   if ( $server_name =~ m/^[\d\.:]+$/ ) {
      # We assume that a server name that is purely numeric (plus ':' and '.')
      # is an IP.
      print $fh "subjectAltName=IP:$server_name\n";
   } else {
      print $fh "subjectAltName=DNS:$server_name\n";
   }
   close $fh;

   # sign it with the CA
   system(
      "openssl", "x509", "-req", "-in", $csr_file,
      "-CA", "keys/ca.crt", "-CAkey", "keys/ca.key", "-set_serial", 1,
      "-out", $cert_file, "-extfile", $ext_file,
   ) == 0 or die "openssl x509 failed $?";
}
