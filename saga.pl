#!/usr/bin/env perl

use strict;


#
# General variables
#
my @EXITS = ("North", "South", "East", "West", "Up", "Down");
my %EXITS_INDEX = map { $EXITS[$_] => $_; } 0..$#EXITS;

my $GAMEFILE = "";
my $SAVEFILE = "";

# Screen
my $DESCRIPTION_LINES = 10;
my $MESSAGE_LINES = 13;
my $SCREEN_WIDTH = 80;
my $DESCRIPTION_BUFFER;
my $MESSAGE_BUFFER;

my %ESCAPE =
(
   "CLEAR_SCREEN" => "\e[2J",
   "CLEAR_EOL" => "\e[0J",
   "CURSOR_HOME" => "\e[H",
   "CURSOR_LINE_N" => "\e[%d;0H"
);

# Known flags
my $FLAG_DARK = 15;
my $FLAG_LIGHT_OUT = 16;

# Known locations
my $LOC_CARRIED = 255;
my $LOC_DESTROYED = 0;
my $LOC_LIMBO; # Need for handling DIE

# Known items
my $ITEM_LAMP = 9;

# Known verbs
my $VERB_AUTO = 0;
my $VERB_GO   = 1;
my $VERB_GET  = 10;
my $VERB_DROP = 18;

# Known nouns
my $NOUN_ANY = 0;
my $NOUN_N = 1;
my $NOUN_S = 2;
my $NOUN_E = 3;
my $NOUN_W = 4;
my $NOUN_U = 5;
my $NOUN_D = 6;

# Tracking
my $NOUN_INPUT;
my $CONTINUED_ACTION = 0;


#
# Database variables
#
my %header;
my @actions;
my @verbs;
my @syn_verbs;
my @nouns;
my @syn_nouns;
my @rooms;
my @messages;
my @items;
my @comments;
my %trailer;

#
# State variables
#
my $LOC_PLAYER;
my $LAMP_TIME;
my $COUNTER;
my $SWAP_ROOM;
my @FLAGS;
my @SAVED_COUNTERS;
my @SAVED_ROOMS;
my @ITEM_LOCATIONS;


#
# Game
#

if (scalar(@ARGV)<1 || scalar(@ARGV)>2)
{
   usage();
}

if ($ARGV[0] eq "-d" && scalar(@ARGV) == 1)
{
   usage();
}

$GAMEFILE = $ARGV[0];

if ($ARGV[0] eq "-d")
{
   $GAMEFILE = $ARGV[1];
}
elsif (scalar(@ARGV) == 2)
{
   $SAVEFILE = $ARGV[1];
}

read_db();

if ($ARGV[0] eq "-d")
{
   dump_all();
   exit 0;
}

init_state();
clear_screen();

while(1)
{
   my $verb;
   my $noun;
   implicit_actions();
   look($LOC_PLAYER);
   get_input(\$verb, \$noun);
   process_input($verb, $noun);
   update_lamp_timer();
}

exit 0;


#
# Game functions
#

sub usage
{
   printf STDERR "Usage: %s [-d] gamefile [savefile]\n", $0;
   printf STDERR "\n";
   printf STDERR "      -d - Output a decompiled representation of the gamefile and exit\n";
   printf STDERR "gamefile - The adventure game data file\n";
   printf STDERR "savefile - Loads a saved game from the file, typically created via \"SAVE GAME\"\n";

   exit 1;
}

sub wrap
{
   my ($s) = @_;
   my $new_s;

   my @chars = split(//, $s);
   my @new_chars;
   my $i = 0;
   while ($i < scalar(@chars))
   {
      my $j = $i;
      while ($j<$i+$SCREEN_WIDTH && $j<scalar(@chars) && $chars[$j] ne "\n")
      {
         $j++;
      }

      if ($j >= scalar(@chars))
      {
         $new_s .= substr($s, $i);
         $i = $j;
      }
      elsif ($chars[$j] eq "\n")
      {
         $new_s .= substr($s, $i, $j - $i + 1);
         $i = $j+1;
      }
      elsif ($j >= $i+$SCREEN_WIDTH)
      {
         my $k = $j-1;
         while ($k>$i && $chars[$k] ne " ")
         {
            $k--;
         }

         if ($chars[$k] eq " ")
         {
            $new_s .= substr($s, $i, $k - $i) . "\n";
            $i = $k + 1;
         }
         else
         {
            $new_s .= substr($s, $i, $j - $i);
            $i = $j;
         }
      }
      else
      {
         die();
      }
   }

   return $new_s;
}

sub output_message
{
   my ($s) = @_;
   $MESSAGE_BUFFER .= $s;
   my $last_char = substr($MESSAGE_BUFFER,-1);

   #This regex was adding extra newline when line was wrapped on exact boundary
   #my $re = qr/(?=.{${SCREEN_WIDTH},})(.{0,${SCREEN_WIDTH}}\n?)( )/;
   #$MESSAGE_BUFFER =~ s/${re}/\1\2\n/g;

   $MESSAGE_BUFFER = wrap($MESSAGE_BUFFER);

   my @lines = split(/\n/, $MESSAGE_BUFFER);
   while (scalar(@lines) < $MESSAGE_LINES)
   {
      unshift @lines, "";
   }

   while (scalar(@lines) > $MESSAGE_LINES)
   {
      shift @lines;
   }

   printf($ESCAPE{'CURSOR_LINE_N'}, $DESCRIPTION_LINES + 2);
   for (my $i=0; $i<$MESSAGE_LINES-1; $i++)
   {
      printf($ESCAPE{'CLEAR_EOL'}."%s\n", $lines[$i]);
   }
   printf($ESCAPE{'CLEAR_EOL'}."%s", $lines[$MESSAGE_LINES-1]);

   $MESSAGE_BUFFER = join("\n", @lines);

   if ($last_char eq "\n")
   {
      printf("\n");
      $MESSAGE_BUFFER .= "\n";
   }

}

sub clear_message
{
   $MESSAGE_BUFFER = '';
}

sub set_description
{
   my ($s) = @_;
   $DESCRIPTION_BUFFER .= $s;

   #This regex was adding extra newline when line was wrapped on exact boundary
   #my $re = qr/(?=.{${SCREEN_WIDTH},})(.{0,${SCREEN_WIDTH}}\n?)( )/;
   #$DESCRIPTION_BUFFER =~ s/${re}/\1\2\n/g;

   $DESCRIPTION_BUFFER = wrap($DESCRIPTION_BUFFER);
}

sub output_description
{
   my @lines = split(/\n/, $DESCRIPTION_BUFFER);
   while (scalar(@lines) < $DESCRIPTION_LINES)
   {
      push @lines, "";
   }

   while (scalar(@lines) > $DESCRIPTION_LINES)
   {
      pop @lines;
   }

   printf($ESCAPE{'CURSOR_HOME'});
   for (my $i=0; $i<$DESCRIPTION_LINES; $i++)
   {
      printf($ESCAPE{'CLEAR_EOL'}."%s\n", $lines[$i]);
   }

   printf("<%s>\n", '-'x($SCREEN_WIDTH-1));
}

sub clear_description
{
   $DESCRIPTION_BUFFER = '';
}

sub clear_screen
{
   printf($ESCAPE{'CLEAR_SCREEN'});
}

sub init_state
{
   $LOC_PLAYER = $header{'START_ROOM'};
   $LAMP_TIME = $header{'LAMP_TIME'};
   $COUNTER = 0;
   $SWAP_ROOM = 0;
   @FLAGS = (0)x32;
   @SAVED_COUNTERS = (0)x16;
   @SAVED_ROOMS = (0)x16;
   foreach my $item (@items)
   {
      push @ITEM_LOCATIONS, $item->{'start_location'};
   }

   if ($SAVEFILE eq "")
   {
      return;
   }

   if (!open FILEHANDLE, '<', $SAVEFILE)
   {
      output_message(sprintf("LOAD ERROR FOR %s: %s\n \n", $SAVEFILE, $!));
      return;
   }

   my $version = read_int();
   my $adventure_number = read_int();

   if ($version != $trailer{'VERSION'} || $adventure_number != $trailer{'ADVENTURE_NUMBER'})
   {
      output_message(sprintf("LOAD ERROR FOR %s: File does not match this game.\n \n", $SAVEFILE));
   }
   else
   {
      $LOC_PLAYER = read_int();
      $LAMP_TIME = read_int();
      $COUNTER = read_int();
      $SWAP_ROOM = read_int();
      @FLAGS = map { read_int(); } 0..$#FLAGS;
      @SAVED_COUNTERS = map { read_int(); } 0..$#SAVED_COUNTERS;
      @SAVED_ROOMS = map { read_int(); } 0..$#SAVED_ROOMS;
      @ITEM_LOCATIONS = map { read_int(); } 0..$#ITEM_LOCATIONS;
   }
   close FILEHANDLE;
}

sub look
{
   my ($room_num) = @_;

   clear_description();

   if ($FLAGS[$FLAG_DARK] && !cond_present($ITEM_LAMP))
   {
      set_description("I can't see. It is too dark!\n");
      output_description();
      return;
   }

   my $room = $rooms[$room_num];
   my $desc = $room->{'desc'};

   if ($desc =~ /^\*/)
   {
      $desc =~ s/^\*//;
   }
   else
   {
      $desc = "I'm in a " . $desc;
   }

   my $items_here = "";
   for (my $i=0; $i<scalar(@ITEM_LOCATIONS); $i++)
   {
      if ($ITEM_LOCATIONS[$i] == $room_num)
      {
         $items_here .= $items[$i]->{'desc'} . ' - ';
      }
   }
   chop $items_here;
   chop $items_here;
   chop $items_here;

   set_description(sprintf("%s\n\n", $desc));
   set_description(sprintf("Obvious exits: %s\n\n", obvious_exits($room->{'exits'})));

   if ($items_here ne "")
   {
      set_description(sprintf("I can also see: %s\n\n", $items_here));
   }

   output_description();
}

sub obvious_exits
{
   my ($exits_ref) = @_;
   my %exits = %{$exits_ref};
   my $s = join(", ", sort {$EXITS_INDEX{$a}<=>$EXITS_INDEX{$b}} keys %exits);
   if ($s eq '')
   {
      $s = 'none.';
   }

   return $s;
}

sub get_input
{
   my ($verb_ref, $noun_ref) = @_;

   my $verb = '';
   my $noun = '';

   output_message("\nTell me what to do ? ");
   my $s = <STDIN>;
   $s =~ s/[\r\n]//d;
   output_message("$s\n");

   if ($s =~ /([^\s]+)\s+([^\s]+)/)
   {
      $verb = $1;
      $noun = $2;
   }
   elsif ($s =~ /([^\s]+)/)
   {
      $verb = $1;
   }

   $NOUN_INPUT = $noun;

   $verb = substr(uc($verb),0,$header{'WORD_LENGTH'});
   $noun = substr(uc($noun),0,$header{'WORD_LENGTH'});

   $$verb_ref = find_verb($verb);
   $$noun_ref = find_noun($noun);

   # Check for shortcuts
   if ($$verb_ref == $VERB_GO)
   {
      my $i = find_dir_shortcut($noun);
      if ($i != 0)
      {
         $$noun_ref = $i;
      }
   }
   elsif ($noun eq '')
   {
      my $i = find_dir_shortcut($verb);
      if ($i != 0)
      {
         $$verb_ref = $VERB_GO;
         $$noun_ref = $i;
      }
      else
      {
         my $i = find_noun($verb);
         if ($i >= 1 && $i <= 6)
         {
            $$verb_ref = $VERB_GO;
            $$noun_ref = $i;
         }
      }
   }

   if ($$verb_ref == -1)
   {
      $$verb_ref = $VERB_AUTO;
   }

   if ($$noun_ref == -1)
   {
      $$noun_ref = $NOUN_ANY;
   }
}

sub process_input
{
   my ($verb, $noun) = @_;

   my $action_result = verb_actions($verb, $noun);

   if ($action_result == 1)
   {
      # handled
      return;
   }
   if ($action_result == -1)
   {
      output_message("It's beyond my power to do that.\n");
      return;
   }
   elsif ($verb == $VERB_GO)
   {
      if ($FLAGS[$FLAG_DARK] && !cond_present($ITEM_LAMP))
      {
         output_message("Dangerous to move in the dark!\n");
      }

      my %exits = %{$rooms[$LOC_PLAYER]->{'exits'}};
      if ($noun == $NOUN_ANY && $NOUN_INPUT eq '')
      {
         output_message("Give me a direction too.\n");
      }
      elsif ($exits{$EXITS[$noun-1]} ne '')
      {
         $LOC_PLAYER = $exits{$EXITS[$noun-1]};
         output_message("OK\n");
         look($LOC_PLAYER);
      }
      elsif ($noun < $NOUN_N || $noun > $NOUN_D)
      {
         output_message("What ?\n");
      }
      elsif ($FLAGS[$FLAG_DARK] && !cond_present($ITEM_LAMP))
      {
         output_message("I fell down and broke my neck.\n");
         output_message("The game is now over.\n");
         exit 0;
      }
      else
      {
         output_message("I can't go in that direction.\n");
      }
   }
   elsif ($verb == $VERB_GET) # Direct GET
   {
      my $s = substr(uc($NOUN_INPUT),0,$header{'WORD_LENGTH'});

      # Use noun list to apply synonyms
      if ($noun != $NOUN_ANY)
      {
         $s = $nouns[$noun];
      }

      my @getable_items = grep {$ITEM_LOCATIONS[$_] == $LOC_PLAYER && $items[$_]->{'noun'} ne '' && ($s eq 'ALL' || $items[$_]->{'noun'} eq $s)} 0..scalar(@ITEM_LOCATIONS);
      my @matching_items = grep {$items[$_]->{'noun'} ne '' && $items[$_]->{'noun'} eq $s} 0..scalar(@ITEM_LOCATIONS);

      if ($s eq 'ALL' && $FLAGS[$FLAG_DARK] && !cond_present($ITEM_LAMP))
      {
         output_message("It's too dark to see.\n");
      }
      elsif ($s ne 'ALL' && scalar(@matching_items) == 0)
      {
         output_message("What ?\n");
      }
      elsif ($s ne 'ALL' && scalar(@getable_items) == 0)
      {
         output_message("It's beyond my power to do that.\n");
      }
      elsif ($s eq 'ALL' && scalar(@getable_items) == 0)
      {
         output_message("Nothing taken.\n");
      }
      else
      {
         my $SAVE_LOC_PLAYER = $LOC_PLAYER;

         foreach my $i (@getable_items)
         {
            my $get_result = 0;

            if ($s eq 'ALL')
            {
               output_message(sprintf("%s: ", $items[$i]->{'desc'}));

               $get_result = verb_actions($VERB_GET, find_noun($items[$i]->{'noun'}));
            }

            if ($get_result == 1)
            {
               # handled
            }
            elsif ($get_result == -1)
            {
               output_message("It's beyond my power to do that.\n");
            }
            elsif ((grep { $_ == $LOC_CARRIED } @ITEM_LOCATIONS) >= $header{'CARRY_LIMIT'})
            {
               output_message("I've too much to carry!\n");
            }
            else
            {
               $ITEM_LOCATIONS[$i] = $LOC_CARRIED;
               output_message("OK\n");
            }

            # If play location changed, we're done with the loop.
            # TODO: Any other cases to end loop?
            # If we're not doing a GET ALL, we're done with the loop (just getting first item)
            if ($LOC_PLAYER != $SAVE_LOC_PLAYER || $s ne 'ALL')
            {
               last;
            }
         }
      }
   }
   elsif ($verb == $VERB_DROP) # Direct DROP
   {
      my $s = substr(uc($NOUN_INPUT),0,$header{'WORD_LENGTH'});

      # Use noun list to apply synonyms
      if ($noun != $NOUN_ANY)
      {
         $s = $nouns[$noun];
      }

      # This differs from spec which says "all items carried by player",
      # however doing that would allow play to drop chigger bites
      # in AdventureLand, etc.
      my @dropable_items = grep {$ITEM_LOCATIONS[$_] == $LOC_CARRIED && $items[$_]->{'noun'} ne '' && ($s eq 'ALL' || $items[$_]->{'noun'} eq $s)} 0..scalar(@ITEM_LOCATIONS);
      my @matching_items = grep {$items[$_]->{'noun'} ne '' && $items[$_]->{'noun'} eq $s} 0..scalar(@ITEM_LOCATIONS);

      if ($s ne 'ALL' && scalar(@matching_items) == 0)
      {
         output_message("What ?\n");
      }
      elsif ($s ne 'ALL' && scalar(@dropable_items) == 0)
      {
         output_message("It's beyond my power to do that.\n");
      }
      elsif ($s eq 'ALL' && scalar(@dropable_items) == 0)
      {
         output_message("Nothing dropped.\n");
      }
      else
      {
         my $SAVE_LOC_PLAYER = $LOC_PLAYER;

         foreach my $i (@dropable_items)
         {
            my $drop_result = 0;

            if ($s eq 'ALL')
            {
               output_message(sprintf("%s: ", $items[$i]->{'desc'}));

               if ($items[$i]->{'noun'} ne '')
               {
                  $drop_result = verb_actions($VERB_DROP, find_noun($items[$i]->{'noun'}));
               }
            }

            if ($drop_result == 1)
            {
               # handled
            }
            else
            {
               $ITEM_LOCATIONS[$i] = $LOC_PLAYER;
               output_message("OK\n");
            }

            # If play location changed, we're done with the loop.
            # TODO: Should we abort or just let further drops happen in new location?
            # TODO: Any other cases to end loop?
            # If we're not doing a DROP ALL, we're done with the loop (just dropping first item)
            if ($LOC_PLAYER != $SAVE_LOC_PLAYER || $s ne 'ALL')
            {
               last;
            }
         }
      }
   }
   else
   {
      output_message("You use word(s) I don't know!\n");
   }
}

sub update_lamp_timer
{
   if ($ITEM_LOCATIONS[$ITEM_LAMP] != $LOC_DESTROYED)
   {
      if ($LAMP_TIME > 0)
      {
         $LAMP_TIME--;

         if ($LAMP_TIME == 0)
         {
            $FLAGS[$FLAG_LIGHT_OUT] = 1;
            if (cond_present($ITEM_LAMP))
            {
               output_message("Light has run out!\n");
            }
         }
         elsif ($LAMP_TIME < 25 && $LAMP_TIME % 5 == 0 && cond_present($ITEM_LAMP))
         {
            output_message("Your light is growing dim.\n");
         }
      }
   }
}

sub find_dir_shortcut
{
   my ($s) = @_;

   my @DIR_SHORTCUT = qw(N S E W U D);
   for (my $i=0; $i<scalar(@DIR_SHORTCUT); $i++)
   {
      if ($s eq $DIR_SHORTCUT[$i])
      {
         return $i + 1;
      }
   }

   return 0;
}

sub find_noun
{
   my ($s) = @_;
   $s = substr(uc($s),0,$header{'WORD_LENGTH'});
   if ($s eq '')
   {
      return -1;
   }

   for (my $i=0; $i<scalar(@nouns); $i++)
   {
      if ($s eq substr(uc($nouns[$i]),0,$header{'WORD_LENGTH'}))
      {
         return $syn_nouns[$i];
      }
   }

   return -1;
}

sub find_verb
{
   my ($s) = @_;
   $s = substr(uc($s),0,$header{'WORD_LENGTH'});
   if ($s eq '')
   {
      return -1;
   }

   for (my $i=0; $i<scalar(@verbs); $i++)
   {
      if ($s eq substr(uc($verbs[$i]),0,$header{'WORD_LENGTH'}))
      {
         return $syn_verbs[$i];
      }
   }

   return -1;
}

sub implicit_actions
{
   foreach my $action (@actions)
   {
      if ($action->{'verb'} != 0)
      {
         next;
      }

      if (rand(100) >= $action->{'noun'})
      {
         next;
      }

      if (!check_conditions($action->{'conditions'}))
      {
         next;
      }

      run_action($action);
   }
}

#
# Returns:
#
#  1 - found and ran a matching action
#  0 - no matching action
# -1 - at least 1 matching action but none run (conditions not passed)
#
sub verb_actions
{
   my ($verb, $noun) = @_;

   my $rcode = 0;

   if ($verb == $VERB_AUTO)
   {
      return $rcode;
   }

   foreach my $action (@actions)
   {
      if ($action->{'verb'} != $verb)
      {
         next;
      }

      if ($action->{'noun'} != $noun && $action->{'noun'} != $NOUN_ANY)
      {
         next;
      }

      $rcode = -1;
      if (run_action($action))
      {
         $rcode = 1;
         last;
      }
   }

   return $rcode;
}

sub continued_actions
{
   my ($num) = @_;

   if ($CONTINUED_ACTION == 0)
   {
      return;
   }

   while (++$num<scalar(@actions) && $actions[$num]->{'verb'}==0 && $actions[$num]->{'noun'}==0)
   {
      run_action($actions[$num]);
   }

   $CONTINUED_ACTION = 0;
}

#
# Returns:
#
# 1 - conditions passed
# 0 - conditions not passed
#
sub run_action
{
   my ($action) = @_;

   $CONTINUED_ACTION = 0;

   if (!check_conditions($action->{'conditions'}))
   {
      return 0;
   }

   # run the action

   # Aborted action is just for processing the GET opcode.
   # It then causes any following opcodes to be skipped

   my @parameters = reverse @{$action->{'parameters'}};
   foreach my $opcode (@{$action->{'opcodes'}})
   {
      if (!process_opcode($opcode, \@parameters))
      {
         # aborted action
         last;
      }
   }

   continued_actions($action->{'num'});
   return 1;
}

sub process_opcode
{
   my ($opcode, $param_ref) = @_;

   if ($opcode == 0)
   {
      # nop;
   }
   elsif ($opcode >= 1 && $opcode <= 51)
   {
      output_message(sprintf("%s\n", $messages[$opcode]));
   }
   elsif ($opcode >= 102)
   {
      output_message(sprintf("%s\n", $messages[$opcode - 50]));
   }
   elsif ($opcode == 52) # GET
   {
      my $item = pop(@{$param_ref});
      my $num_carried = grep { $_ == $LOC_CARRIED } @ITEM_LOCATIONS;

      if ($num_carried < $header{'CARRY_LIMIT'})
      {
         $ITEM_LOCATIONS[$item] = $LOC_CARRIED;
      }
      else
      {
         output_message("I've too much to carry!\n");
         return 0;
      }
   }
   elsif ($opcode == 53)  # DROP
   {
      my $item = pop(@{$param_ref});
      $ITEM_LOCATIONS[$item] = $LOC_PLAYER;
   }
   elsif ($opcode == 54) #GOTO
   {
      my $room = pop(@{$param_ref});
      $LOC_PLAYER = $room;
   }
   elsif ($opcode == 55)  # DESTROY
   {
      my $item = pop(@{$param_ref});
      $ITEM_LOCATIONS[$item] = $LOC_DESTROYED;
   }
   elsif ($opcode == 56) # SET_DARK
   {
      $FLAGS[$FLAG_DARK] = 1;
   }
   elsif ($opcode == 57) # CLEAR_DARK
   {
      $FLAGS[$FLAG_DARK] = 0;
   }
   elsif ($opcode == 58) # SET_FLAG
   {
      my $flag = pop(@{$param_ref});
      $FLAGS[$flag] = 1;
   }
   elsif ($opcode == 59)  # DESTROY2
   {
      my $item = pop(@{$param_ref});
      $ITEM_LOCATIONS[$item] = $LOC_DESTROYED;
   }
   elsif ($opcode == 60) # CLEAR_FLAG
   {
      my $flag = pop(@{$param_ref});
      $FLAGS[$flag] = 0;
   }
   elsif ($opcode == 61) # DIE
   {
      $FLAGS[$FLAG_DARK] = 0;
      $LOC_PLAYER = $LOC_LIMBO;
   }
   elsif ($opcode == 62) # PUT
   {
      my $item = pop(@{$param_ref});
      my $room = pop(@{$param_ref});
      $ITEM_LOCATIONS[$item] = $room;
   }
   elsif ($opcode == 63) # GAME_OVER
   {
      output_message("The game is now over.\n");
      exit 0;
   }
   elsif ($opcode == 64) # LOOK
   {
      look($LOC_PLAYER);
   }
   elsif ($opcode == 65) # SCORE
   {
      my $num_scored = grep { $ITEM_LOCATIONS[$_] == $header{'TREASURE_ROOM'} && $items[$_]->{'treasure'} == 1 } 0..$#ITEM_LOCATIONS;
      if ($header{'NUM_TREASURES'} != 0)
      {
         output_message(sprintf("I've stored %d treasures.  On a scale of 0 to 100, that rates %d.\n", $num_scored, int(100*$num_scored/$header{'NUM_TREASURES'})));
      }

      if ($num_scored >= $header{'NUM_TREASURES'})
      {
         output_message("Well done.\n");
         output_message("The game is now over.\n");
         exit 0;
      }
   }
   elsif ($opcode == 66) # INVENTORY
   {
      output_message("I'm carrying:\n");
      my @carrying = grep { $ITEM_LOCATIONS[$_] == $LOC_CARRIED } 0..$#ITEM_LOCATIONS;
      if (scalar(@carrying) == 0)
      {
         output_message("Nothing.\n");
      }
      else
      {
         output_message(sprintf("%s.\n", join(" - ", map { $items[$_]->{'desc'} } @carrying)));
      }
   }
   elsif ($opcode == 67) # SET_FLAG0
   {
      $FLAGS[0] = 1;
   }
   elsif ($opcode == 68) # CLEAR_FLAG0
   {
      $FLAGS[0] = 0;
   }
   elsif ($opcode == 69) # REFILL_LAMP
   {
      $LAMP_TIME = $header{'LAMP_TIME'};
      $ITEM_LOCATIONS[$ITEM_LAMP] = $LOC_CARRIED;
      $FLAGS[$FLAG_LIGHT_OUT] = 0;
   }
   elsif ($opcode == 70) # CLEAR
   {
      clear_message();
      clear_screen();
   }
   elsif ($opcode == 71) # SAVE_GAME
   {
      output_message("Enter save file name: ");
      my $filename = <STDIN>;
      $filename =~ s/[\r\n]//d;
      output_message("$filename\n");

      my $answer = "Y";
      if (-e "$filename")
      {
         $answer = "";
         while ($answer ne "Y" && $answer ne "N")
         {
            output_message(sprintf("Overwrite file %s (Y/N): ", $filename));
            $answer = <STDIN>;
            $answer =~ s/[\r\n]//d;
            output_message("$answer\n");
            $answer = substr(uc($answer),0,1);
         }
      }

      if ($answer eq "N")
      {
      }
      elsif (!open(FH, '>', $filename))
      {
         output_message(sprintf("SAVE ERROR FOR %s: %s\n \n", $filename, $!));
      }
      else
      {
         print FH $trailer{'VERSION'} . "\n";
         print FH $trailer{'ADVENTURE_NUMBER'} . "\n";
         print FH $LOC_PLAYER . "\n";
         print FH $LAMP_TIME . "\n";
         print FH $COUNTER . "\n";
         print FH $SWAP_ROOM . "\n";
         foreach my $flag (@FLAGS) { print FH $flag . "\n"; }
         foreach my $counter (@SAVED_COUNTERS) { print FH $counter . "\n"; }
         foreach my $room (@SAVED_ROOMS) { print FH $room . "\n"; }
         foreach my $item (@ITEM_LOCATIONS) { print FH $item . "\n"; }
         close(FH);

         output_message(sprintf("Game saved to file %s.\n", $filename));
      }
   }
   elsif ($opcode == 72) # SWAP
   {
      my $item1 = pop(@{$param_ref});
      my $item2 = pop(@{$param_ref});
      my $loc1 = $ITEM_LOCATIONS[$item1];
      $ITEM_LOCATIONS[$item1] = $ITEM_LOCATIONS[$item2];
      $ITEM_LOCATIONS[$item2] = $loc1;
   }
   elsif ($opcode == 73) # CONTINUE
   {
      $CONTINUED_ACTION = 1;
   }
   elsif ($opcode == 74) # SUPER_GET
   {
      my $item = pop(@{$param_ref});
      $ITEM_LOCATIONS[$item] = $LOC_CARRIED;
   }
   elsif ($opcode == 75) # PUT_WITH
   {
      my $item1 = pop(@{$param_ref});
      my $item2 = pop(@{$param_ref});
      $ITEM_LOCATIONS[$item1] = $ITEM_LOCATIONS[$item2];
   }
   elsif ($opcode == 76) # LOOK2
   {
      look($LOC_PLAYER);
   }
   elsif ($opcode == 77) # DEC_COUNTER
   {
      if ($COUNTER >= 0)
      {
         $COUNTER--;
      }
   }
   elsif ($opcode == 78) # PRINT_COUNTER
   {
      output_message(sprintf("%d ", $COUNTER));
   }
   elsif ($opcode == 79) # SET_COUNTER
   {
      my $counter = pop(@{$param_ref});
      $COUNTER = $counter;
   }
   elsif ($opcode == 80) # SWAP_ROOM
   {
      my $loc = $SWAP_ROOM;
      $SWAP_ROOM = $LOC_PLAYER;
      $LOC_PLAYER = $loc;
   }
   elsif ($opcode == 81) # SWAP_COUNTER
   {
      my $counter = pop(@{$param_ref});
      my $val = $SAVED_COUNTERS[$counter];
      $SAVED_COUNTERS[$counter] = $COUNTER;
      $COUNTER = $val;
   }
   elsif ($opcode == 82) # ADD_TO_COUNTER
   {
      my $counter = pop(@{$param_ref});
      $COUNTER += $counter;
      if ($COUNTER < -1)
      {
         $COUNTER = -1;
      }
      if ($COUNTER > 32767)
      {
         $COUNTER = 32767;
      }
   }
   elsif ($opcode == 83) # SUBTRACT_FROM_COUNTER
   {
      my $counter = pop(@{$param_ref});
      $COUNTER -= $counter;
      if ($COUNTER < -1)
      {
         $COUNTER = -1;
      }
      if ($COUNTER > 32767)
      {
         $COUNTER = 32767;
      }
   }
   elsif ($opcode == 84) # PRINT_NOUN
   {
      #TODO
      output_message(sprintf("%s", $NOUN_INPUT));
   }
   elsif ($opcode == 85) # PRINTLN_NOUN
   {
      #TODO
      output_message(sprintf("%s\n", $NOUN_INPUT));
   }
   elsif ($opcode == 86) # PRINTLN
   {
      #TODO
      output_message("\n");
   }
   elsif($opcode == 87) # SWAP_SPECIFIC_ROOM
   {
      my $room = pop(@{$param_ref});
      my $loc = $SAVED_ROOMS[$room];
      $SAVED_ROOMS[$room] = $LOC_PLAYER;
      $LOC_PLAYER = $loc;
   }
   elsif ($opcode == 88) # PAUSE
   {
      #TODO
      sleep(2);
   }
   elsif ($opcode == 89) # DRAW
   {
   }

   return 1;
}

sub check_conditions
{
   my ($conditions) = @_;
   foreach my $condition (@{$conditions})
   {
      if (!check_condition($condition))
      {
         return 0;
      }
   }

   return 1;
}

sub check_condition
{
   my ($condition) = @_;
   my $cond = $condition->{'condition'};
   my $arg = $condition->{'argument'};

   if ( ($cond == 1 && cond_carried($arg))     || # carried
        ($cond == 2 && cond_here($arg))        || # here
        ($cond == 3 && cond_present($arg))     || # present
        ($cond == 4 && cond_at($arg))          || # at
        ($cond == 5 && !cond_here($arg))       || # not here
        ($cond == 6 && !cond_carried($arg))    || # not carried
        ($cond == 7 && !cond_at($arg))         || # not at
        ($cond == 8 && cond_flag_set($arg))    || # flag set
        ($cond == 9 && !cond_flag_set($arg))   || # flag not set
        ($cond ==10 && cond_loaded())          || # loaded
        ($cond ==11 && !cond_loaded())         || # not loaded
        ($cond ==12 && !cond_present($arg))    || # not present
        ($cond ==13 && cond_exists($arg))      || # exists
        ($cond ==14 && !cond_exists($arg))     || # not exists
        ($cond ==15 && cond_counter_le($arg))  || # counter_le
        ($cond ==16 && !cond_counter_le($arg)) || # counter_gt
        ($cond ==17 && !cond_moved($arg))      || # not moved
        ($cond ==18 && cond_moved($arg))       || # moved
        ($cond ==19 && cond_counter_eq($arg))     # counter_eq
      )
   {
      return 1;
   }
}

sub cond_carried { my ($item) = @_; return $ITEM_LOCATIONS[$item] == $LOC_CARRIED; }
sub cond_here { my ($item) = @_; return $ITEM_LOCATIONS[$item] == $LOC_PLAYER; }
sub cond_present { my ($item) = @_; return cond_carried($item) || cond_here($item); }
sub cond_at { my ($room) = @_; return $room == $LOC_PLAYER; }
sub cond_flag_set { my ($flag) = @_; return $FLAGS[$flag] == 1; }
sub cond_loaded { return grep(/^$LOC_CARRIED$/,@ITEM_LOCATIONS); }
sub cond_exists { my ($item) = @_; return $ITEM_LOCATIONS[$item] != $LOC_DESTROYED; }
sub cond_counter_le { my ($counter) = @_; $COUNTER <= $counter; }
sub cond_moved { my ($item) = @_; return $ITEM_LOCATIONS[$item] != $items[$item]->{'start_location'}; }
sub cond_counter_eq { my ($counter) = @_; $COUNTER == $counter; }


#
# Database functions
#

sub read_db
{
   open FILEHANDLE, '<', $GAMEFILE or die $!;
   read_header();
   read_actions();
   read_vocab();
   read_rooms();
   read_messages();
   read_items();
   read_comments();
   read_trailer();
   $LOC_LIMBO = scalar(@rooms) - 1;
   close FILEHANDLE;
}

sub read_header
{
   $header{'STRING_SPACE'} = read_int();
   $header{'NUM_ITEMS'} = read_int() + 1;
   $header{'NUM_ACTIONS'} = read_int() + 1;
   $header{'NUM_VOCAB'} = read_int() + 1;
   $header{'NUM_ROOMS'} = read_int() + 1;
   $header{'CARRY_LIMIT'} = read_int();
   $header{'START_ROOM'} = read_int();
   $header{'NUM_TREASURES'} = read_int();
   $header{'WORD_LENGTH'} = read_int();
   $header{'LAMP_TIME'} = read_int();
   $header{'NUM_MESSAGES'} = read_int() + 1;
   $header{'TREASURE_ROOM'} = read_int();
}

sub read_actions
{
   for (my $i=0; $i<$header{'NUM_ACTIONS'}; $i++)
   {
      my %action;
      my $x;

      $x = read_int();
      $action{'verb'} = int($x/150);
      $action{'noun'} = $x % 150;

      my @conditions;
      my @parameters;
      for (my $j=0; $j<5; $j++)
      {
         $x = read_int();
         my $condition = $x % 20;
         my $argument = int($x / 20);

         if ($condition == 0)
         {
            push @parameters, $argument;
         }
         else
         {
            push @conditions, {'condition' => $condition, 'argument' => $argument};
         }
      }

      my @opcodes;
      for (my $j=0; $j<2; $j++)
      {
         $x = read_int();
         my $op1 = int($x / 150);
         my $op2 = $x % 150;
         if ($op1 != 0)
         {
            push @opcodes, $op1;
         }
         if ($op2 != 0)
         {
            push @opcodes, $op2;
         }
      }

      $action{'conditions'} = \@conditions;
      $action{'parameters'} = \@parameters;
      $action{'opcodes'} = \@opcodes;
      $action{'num'} = $i;

      push @actions, \%action;
   }
}

sub read_vocab
{
   my $syn_verb = 0;
   my $syn_noun = 0;
   for (my $i=0; $i<$header{'NUM_VOCAB'}; $i++)
   {
      # Verb
      my $s = read_quoted_str();
      if ($s =~ /^\*/)
      {
         $s =~ s/^\*//;
      }
      else
      {
         $syn_verb = $i;
      }
      push @verbs, $s;
      push @syn_verbs, $syn_verb;

      # Noun
      $s = read_quoted_str();
      if ($s =~ /^\*/)
      {
         $s =~ s/^\*//;
      }
      else
      {
         $syn_noun = $i;
      }
      push @nouns, $s;
      push @syn_nouns, $syn_noun;
   }
}

sub read_rooms
{
   for (my $i=0; $i<$header{'NUM_ROOMS'}; $i++)
   {
      my %room;
      my %exits;
      foreach my $exit (@EXITS)
      {
         my $x = read_int();
         if ($x != 0)
         {
            $exits{$exit} = $x;
         }
      }
      $room{'exits'} = \%exits;

      $room{'desc'} = read_quoted_str();

      push @rooms, \%room;
   }
}

sub read_messages
{
   for (my $i=0; $i<$header{'NUM_MESSAGES'}; $i++)
   {
      my $s = read_quoted_str();
      push @messages, $s;
   }
}

sub read_items
{
   for (my $i=0; $i<$header{'NUM_ITEMS'}; $i++)
   {
      push @items, read_quoted_str();
   }
}

sub read_comments
{
   for (my $i=0; $i<$header{'NUM_ACTIONS'}; $i++)
   {
      push @comments, read_quoted_str();
   }
}

sub read_trailer
{
   $trailer{'VERSION'} = read_int();
   $trailer{'ADVENTURE_NUMBER'} = read_int();
   $trailer{'CHECKSUM'} = read_int();
}

sub read_int
{
   my $s = <FILEHANDLE>;
   return int($s);
}

sub read_str
{
   my $s = <FILEHANDLE>;
   $s =~ s/[\r\n]//g;
   return $s;
}

sub read_quoted_str
{
   my @lines;
   my $n = 0;
   my $location = "";

   while (1)
   {
      my $s = read_str();
      my @quotes = $s =~ /"/g;
      $n += scalar(@quotes);

      if ($s =~ /" *(-?\d+) *$/)
      {
         $location = $1;
         $s =~ s/" *-?\d+ *$//;
      }

      $s =~ s/"//g;
      push @lines, $s;

      if ($n > 1)
      {
         last;
      }
   }

   $lines[0] =~ s/^"//;
   $lines[scalar(@lines)-1] =~ s/"$//;

   my $s = join("\n", @lines);
   $s =~ s/`/"/g;

   if ($location ne "")
   {
      my %item;

      if ($s =~ /\/([^\/]+)\//)
      {
         if ($1 ne '')
         {
            $item{'noun'} = $1;
         }

         $s =~ s/\/[^\/]+\///;
      }

      $item{'desc'} = $s;

      if ($s =~ /^\*/)
      {
         $item{'treasure'} = 1;
      }

      if ($location == -1 || $location == 255)
      {
         $location = $LOC_CARRIED;
      }

      $item{'start_location'} = $location;

      return \%item;
   }
   else
   {
      return $s;
   }
}


#
# Debugging
#

sub dump_all
{
   %ESCAPE = map { "_".$_ => delete $ESCAPE{$_}; } (keys %ESCAPE);
   dump_actions();
   dump_vocab();
   dump_rooms();
   dump_messages();
   dump_items();
   dump_trailer();
   %ESCAPE = map { substr($_,1) => delete $ESCAPE{$_}; } (keys %ESCAPE);
}

sub dump_actions
{
   foreach my $action (@actions)
   {
      dump_action($action);
   }
}

sub dump_action
{
   my ($action) = @_;

   printf("\n");
   printf("%d: ", $action->{'num'});

   my $comment = "";
   if ( $action->{'num'} < scalar(@comments) && $comments[$action->{'num'}] ne '')
   {
      $comment = " ; " . $comments[$action->{'num'}];
   }

   if ($action->{'verb'} == 0 && $action->{'noun'} == 0)
   {
      printf("CONTINUED%s\n", $comment);
   }
   elsif ($action->{'verb'} == 0)
   {
      printf("IMPLICIT %d%%%s\n", $action->{'noun'}, $comment);
   }
   else
   {
      printf("verb %d (%s), noun %d (%s)%s\n", $action->{'verb'}, $verbs[$action->{'verb'}], $action->{'noun'}, $nouns[$action->{'noun'}], $comment);
   }

   if (scalar(@{$action->{'conditions'}}) > 0)
   {
      foreach my $condition (@{$action->{'conditions'}})
      {
         printf("  %s\n", dump_condition($condition));
      }
   }

   if (scalar(@{$action->{'opcodes'}}) > 0)
   {
      my @opcodes = @{$action->{'opcodes'}};
      printf("  opcodes: %s\n", join(",",@{$action->{'opcodes'}}));
   }

   if (scalar(@{$action->{'parameters'}}) > 0)
   {
      printf("  parameters: %s\n", join(",",@{$action->{'parameters'}}));
   }

   my @parameters = reverse @{$action->{'parameters'}};
   if (scalar(@{$action->{'opcodes'}}) > 0)
   {
      printf("  :\n");
   }
   foreach my $opcode (@{$action->{'opcodes'}})
   {
      printf("  %d: %s\n", $opcode, dump_opcode($opcode, \@parameters));
   }
}

sub dump_condition
{
   my ($condition) = @_;

   my @CONDITIONS = ( "param", "carried", "here", "present", "at", "not here", "not carried",
                      "not at", "flag set", "flag not set", "loaded", "not loaded", "not present",
                      "exists", "not exists", "counter_le", "counter_gt", "not moved", "moved",
                      "counter_eq" );

   my $arg_s;
   my $cond = $condition->{'condition'};
   if(0) {$arg_s = "param";}
   elsif($cond==1) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==2) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==3) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==4) {$arg_s = "ROOM ".$rooms[$condition->{'argument'}]->{'desc'};}
   elsif($cond==5) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==6) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==7) {$arg_s = "ROOM ".$rooms[$condition->{'argument'}]->{'desc'};}
   elsif($cond==8) {$arg_s = "FLAG";}
   elsif($cond==9) {$arg_s = "FLAG";}
   elsif($cond==10) {$arg_s = "N/A";}
   elsif($cond==11) {$arg_s = "N/A";}
   elsif($cond==12) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==13) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==14) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==15) {$arg_s = "VALUE";}
   elsif($cond==16) {$arg_s = "VALUE";}
   elsif($cond==17) {$arg_s = "VALUE";}
   elsif($cond==18) {$arg_s = "ITEM ".$items[$condition->{'argument'}]->{'desc'};}
   elsif($cond==19) {$arg_s = "VALUE";}
   else {$arg_s = "unknown";}

   my $s = sprintf("condition %d(%s), argument %d(%s)", $condition->{'condition'}, $CONDITIONS[$condition->{'condition'}], $condition->{'argument'}, $arg_s);

   return $s;
}

sub dump_opcode
{
   my ($opcode, $param_ref) = @_;

   # messages
   if ($opcode >= 1 && $opcode <= 51)
   {
      return "MSG " . $messages[$opcode];
   }
   elsif ($opcode >= 102)
   {
      return "MSG " . $messages[$opcode - 50];
   }

   if($opcode==0) {return "NOP";}
   elsif($opcode==52) {return "GET " . $items[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==53) {return "DROP " . $items[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==54) {return "GOTO " . $rooms[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==55) {return "DESTROY " . $items[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==56) {return "SET_DARK";}
   elsif($opcode==57) {return "CLEAR_DARK";}
   elsif($opcode==58) {return "SET_FLAG " . pop(@{$param_ref});}
   elsif($opcode==59) {return "DESTROY2 " . $items[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==60) {return "CLEAR_FLAG " . pop(@{$param_ref});}
   elsif($opcode==61) {return "DIE";}
   elsif($opcode==62) {return "PUT " . $items[pop(@{$param_ref})]->{'desc'} . "," . $rooms[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==63) {return "GAME_OVER";}
   elsif($opcode==64) {return "LOOK";}
   elsif($opcode==65) {return "SCORE";}
   elsif($opcode==66) {return "INVENTORY";}
   elsif($opcode==67) {return "SET_FLAG0";}
   elsif($opcode==68) {return "CLEAR_FLAG0";}
   elsif($opcode==69) {return "REFILL_LAMP";}
   elsif($opcode==70) {return "CLEAR";}
   elsif($opcode==71) {return "SAVE_GAME";}
   elsif($opcode==72) {return "SWAP " . $items[pop(@{$param_ref})]->{'desc'} . "," . $items[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==73) {return "CONTINUE";}
   elsif($opcode==74) {return "SUPERGET " . $items[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==75) {return "PUT_WITH " . $items[pop(@{$param_ref})]->{'desc'} . "," . $items[pop(@{$param_ref})]->{'desc'};}
   elsif($opcode==76) {return "LOOK2";}
   elsif($opcode==77) {return "DEC_COUNTER";}
   elsif($opcode==78) {return "PRINT_COUNTER";}
   elsif($opcode==79) {return "SET_COUNTER " . pop(@{$param_ref});}
   elsif($opcode==80) {return "SWAP_ROOM";}
   elsif($opcode==81) {return "SWAP_COUNTER " . pop(@{$param_ref});}
   elsif($opcode==82) {return "ADD_TO_COUNTER " . pop(@{$param_ref});}
   elsif($opcode==83) {return "SUBTRACT_FROM_COUNTER " . pop(@{$param_ref});}
   elsif($opcode==84) {return "PRINT_NOUN";}
   elsif($opcode==85) {return "PRINTLN_NOUN";}
   elsif($opcode==86) {return "PRINTLN";}
   elsif($opcode==87) {return "SWAP_SPECIFIC_ROOM " . pop(@{$param_ref});}
   elsif($opcode==88) {return "PAUSE";}
   elsif($opcode==89) {return "DRAW";}
   else {return "unknown";}
}

sub dump_vocab
{
   my $i = 0;
   foreach my $verb (@verbs)
   {
      printf("Verb %d %s", $i, $verbs[$i]);
      if ($syn_verbs[$i] != $i)
      {
         printf(" (%s)", $verbs[$syn_verbs[$i]]);
      }
      printf("\n");

      $i++;
   }

   $i = 0;
   foreach my $noun (@nouns)
   {
      printf("Noun %d %s", $i, $nouns[$i]);
      if ($syn_nouns[$i] != $i)
      {
         printf(" (%s)", $nouns[$syn_nouns[$i]]);
      }
      printf("\n");

      $i++;
   }
}

sub dump_rooms
{
   my $i = 0;
   foreach my $room (@rooms)
   {
      printf("Room %d\n", $i);
      printf("Obvious exits: %s\n", obvious_exits($room->{'exits'}));
      my %exits = %{$room->{'exits'}};
      foreach my $key (sort {$EXITS_INDEX{$a}<=>$EXITS_INDEX{$b}} keys %{$room->{'exits'}})
      {
         printf("%s: %s\n", $key, $rooms[$exits{$key}]->{'desc'});
      }
      printf("Desc:\n%s\n", $room->{'desc'});
      printf("\n");
      look($i);
      printf("\n");
      $i++;
   }
}

sub dump_messages
{
   my $i = 0;
   foreach my $message (@messages)
   {
      printf("Message %d\n", $i);
      printf("%s\n", $message);
      printf("\n");
      $i++;
   }
}

sub dump_items
{
   my $i = 0;
   foreach my $item (@items)
   {
      printf("Item %d", $i);
      if ($item->{'noun'} ne '')
      {
         printf(" (%s)", $item->{'noun'});
      }
      printf("\n");
      printf("%s (loc: %d)\n", $item->{'desc'}, $ITEM_LOCATIONS[$i]);
      printf("\n");
      $i++;
   }
}

sub dump_trailer
{
   printf("Version: %.2f\n", $trailer{'VERSION'} / 100);
   printf("Adventure number: %d\n", $trailer{'ADVENTURE_NUMBER'});
   printf("Checksum: %d\n", $trailer{'CHECKSUM'});
   printf("Checksum computed: %d\n", 2 * ($header{'NUM_ACTIONS'}-1) + $header{'NUM_ITEMS'}-1 + $trailer{'VERSION'});
}
