test "GET /register yields a set of flows",
   requires => [qw( http_clients )],

   check => sub {
      my ( $HTTP ) = @_;
      my $http = $HTTP->[0];

      $http->do_request_json(
         uri => "/register",
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list\n";

         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];

            # TODO(paul): Spec is a little vague here. Spec says that every
            #   option needs a 'stages' key, but the implementation omits it
            #   for options that have only one stage in their flow.
            ref $flow->{stages} eq "ARRAY" or defined $flow->{type} or
               die "Expected flow[$idx] to have 'stages' as a list or a 'type'\n";
         }

         Future->done(1);
      });
   };
