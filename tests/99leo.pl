test "Day job",
   requires => [
      local_paul_fixture(), local_matthew_fixture(),
   ],

   do => sub {
      my ( $leo, $matthew ) = @_;

      try_repeat( sub {
         $matthew->get_job_for( $leo )
         ->then( sub {
            $leo->attempt_acquire_contract_from( $amdocs )
            ->expect_Complications;
         })->then( sub {
            try_repeat_until_success( sub {
               $leo->write_telegram_bridge_with( $telegram_library )
               ->else_with_f(sub {
                  $telegram_library = $telegram_library->next;
               });
            }, timeout => time_until_demo() );
         })->then( sub {
            Future->needs_all(
               $leo->fill_in_working_hours( $amdocs ),
               $leo->fill_in_working_hours( $agency ),
            );
         })->expect_$
         ->then( sub {
            $leo->do_some_bridge_"stuff"()
         })->then( sub {
            await $kegan;
         })->expect_timeout
         ->then( sub {
            await $amdocs->get_funding();
         })
      });
   };

sub time_until_demo() return -3600;
