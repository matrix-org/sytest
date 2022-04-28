# -*- coding: utf-8 -*-
# Copyright 2021 The Matrix.org Foundation C.I.C.
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

# crypto-related utility functions for SyTest


package SyTest::Crypto;

use Crypt::Ed25519;

use Exporter qw( import );
our @EXPORT_OK = qw( ed25519_nacl_keypair );

=head2 ed25519_nacl_keypair

    ( $public_key, $secret_key ) = ed25519_nacl_keypair( [ $seed ] );

A drop in replacement for Crypt::NaCl::Sodium->sign->keypair.

Generate a new Ed25519 keypair, in a format compatible with the NaCl API.

If the optional seed is given, that is used to determiniatically derive the
public and secret key.

NaCl (http://nacl.cr.yp.to/) uses "secret keys" which are actually 64-byte
tuples of (seed, public key) (whereas most other libraries either use just the
seed, or a "preprocessed" 64-byte private key, which is deterministically
derived from the seed. SyTest includes a bunch of code which relies on the NaCl
format, so for now we have this shim to create them.

Deprecated: it's better just to use the `Crypt::Ed25519::eddsa_*` APIs directly.

=cut

sub ed25519_nacl_keypair {
   my ( $seed ) = @_;
   $seed //= Crypt::Ed25519::eddsa_secret_key();
   my $public_key = Crypt::Ed25519::eddsa_public_key($seed);
   return ( $public_key, $seed.$public_key );
}

