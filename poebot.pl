#!/usr/bin/perl
use strict;
use warnings;
use POE;
use POE::Component::IRC::State;
use POE::Component::SSLify;
use YAML;
use feature qw/say switch/;

use URI::Title qw/title/;
use Data::Dumper;
use Weather::Google;

sub NULL { undef; }

my ($config,$behave,$chan);
my $chanhash = {};

$config = YAML::LoadFile("bot/etc.yaml");

my ($irc) = POE::Component::IRC::State->spawn();

sub loadconfig {
	if (defined $behave->{chans}) {
		for (keys %$behave) {
			delete $behave->{$_};
		}
	}
	if (defined $chanhash) {
		for (keys %$chanhash) {
			delete $chanhash->{$_};
		}
	}
	$behave = YAML::LoadFile("bot/behaviour.yaml");
	
	$chan = $behave->{'chan'};
	my $ima = chanlist();
	my @ch;
	foreach my $cha(@$chan) {
		my $naym = $cha->{'name'};
		push(@ch,$naym);
		$chanhash->{$naym} = $cha;
	}
	foreach my $k(keys %$ima) { #leave channels not hardcoded
		if(grep $_ eq $k, @ch) {
			my $flags = $ima->{$k};
		}
		else {
			$irc->yield(part => $k => "It was a lovely dream...");
		}
	}
	foreach my $zzz(@ch) {
		$irc->yield(join => $zzz) if !($ima->{$zzz});
	}

}


loadconfig;
POE::Session->create(
        inline_states => {
                _start          =>      \&bot_start,
                irc_001         =>      \&on_connect,
		irc_disconnected=>	\&bot_reconnect,
		irc_error	=>	\&bot_reconnect,
		irc_socketerr	=>	\&bot_reconnect,
		irc_ping	=>	\&on_ping,
		autoping	=>	\&bot_do_autoping,
                irc_public      =>      \&on_public,
		irc_msg		=>	\&on_msg,
		irc_notice	=>	\&on_notice,
#		irc_snotice	=>	\&on_notice,
		irc_ctcp	=>	\&on_ctcp,
		irc_mode	=>	\&on_mode,
		irc_kick	=>	\&on_kick,
		irc_join	=>	\&on_join,
		irc_whois	=>	\&on_whois,
		irc_307		=>	\&on_whois_ident,#has identified for this nick
		irc_nick	=>	\&on_nick,
		irc_quit	=>	\&on_quit,
		irc_part	=>	\&on_quit,

		irc_332		=>	\&NULL,#topic contents
		irc_333		=>	\&NULL,#topic mod time

		irc_353		=>	\&NULL,#names
		irc_366		=>	\&NULL,#end of names list

		irc_311		=>	\&NULL,#whois
		irc_312		=>	\&NULL,#whois
		irc_671		=>	\&NULL,#whois-SSL
		irc_318		=>	\&NULL,#end of whoislist
		irc_319		=>	\&NULL,#whois channel list

		irc_372		=>	\&NULL, #MOTD
		irc_ctcp_action	=>	\&NULL,
		irc_375		=>	\&NULL, #MOTD
		irc_376		=>	\&NULL, #MOTD
		irc_ctcp_version=>	\&NULL,
		_default	=>	\&handle_default,
        }
);

sub bot_start {
	my ($kernel,$heap) = @_[KERNEL,HEAP];
	$irc->yield(register => "all");
	$irc->yield(connect=> {
		Nick		=>	$config->{'nick'},
		Username	=>	$config->{'uname'},
		Ircname		=>	$config->{'iname'},
		Server		=>	$config->{'serv'},
		Port		=>	$config->{'port'},
		UseSSL		=>	$config->{'ssl'},
		}
	);
}

sub on_connect {
	my ($kernel,$heap) = @_[KERNEL,HEAP];
	my $pass = $config->{'pass'};
	$irc->yield(privmsg => 'NickServ' => "identify $pass");
	foreach my $cj(@$chan) {
		$irc->yield(join => ($cj->{'name'}));
	}
	$heap->{seen_traffic} = 1;
	$kernel->delay(autoping=>300);

	sleep 30;
	
	my $channuls = $irc->channels();
	say Dumper($channuls);

}

sub bot_do_autoping {
	my ($kernel,$heap) = @_[KERNEL,HEAP];
	say "Autopinging...";
	$kernel->post(poco_irc => userhost => "saa")
		unless $heap->{seen_traffic};
	$heap->{seen_traffic} = 0;
	$kernel->delay(autoping=>300);
}

sub bot_reconnect {
	my $kernel = $_[KERNEL];
	say "Reconnecting...";
	$kernel->delay(autoping => undef);
	$kernel->delay(_start => 60);
}

sub on_ping {
	my ($kernel,$who) = @_[KERNEL,ARG0];
	say "PING received from $who.";
}

sub handle_default { #this is from http://poe.perl.org/?POE_Cookbook/IRC_Bot_Debugging
eval {
	  my ($event, $args) = @_[ARG0 .. $#_];
	  print "unhandled $event\n";
	  my $arg_number = 0;
	  foreach (@$args) {
	    print "  ARG$arg_number = ";
	    if (ref($_) eq 'ARRAY') {
	      print "$_ = [", join(", ", @$_), "]\n";
	    }
	    else {
	      print "'$_'\n";
	    }
	    $arg_number++;
	  }
} unless ($config->{'debug'} eq 0);
  return 0;    # Don't handle signals.
}


#
#content from here on
#

my $colorCodeMap = {
	r => 5,
	o => 4,
	y => 7,
	Y => 8,
	g => 3,
	G => 9,
	c => 10,
	C => 11,
	b => 2,
	B => 12,
	m => 6,
	M => 13,
	0 => 1,
	1 => 14,
	2 => 15,
	w => 0,
};

sub color {
	my ($fg,$bg,$t) = @_;
	my $m = "\003$fg";
	$m = $m . ",$bg" if defined($bg);
	my $o = ord(substr($t,0,1));
	if (($o >=48 and $o <= 57) or $o==44) {
		$m .= "\26\26";
	}
	$m = $m . $t . "\x0F";
	return $m;
}

sub rainbow {
	my ($t,$pattern) = @_;
	my $output;
	return undef if !defined $t;
	if (!defined $pattern) {
		$pattern = 'rrooyyYYGGggccCCBBbbmmMM';
	}
	foreach my $line(split(/\r?\n/,$t)) {
		my $len = length($line);
		my $i = 0;
		my $sty = length($pattern);
		foreach my $char(split('',$line)) {
			my $color = substr($pattern,($i % $sty),1);
			$color = $colorCodeMap->{$color};
			$output .= color($color,undef,$char);
			$i++;
		}
		$output .= "\n";
	}
	return $output;
}

sub on_msg {
	my ($kernel,$who,$where,$msg) = @_[KERNEL,ARG0,ARG1,ARG2];
	my $nick    = (split /!/, $who)[0];
	my $channel = $where->[0];
	my $ts      = scalar localtime;
	print "[$ts] <$nick:$channel> $msg\n";
	given($nick) {
		when(/^shelf$/) {
			if ($msg =~ /^\.join\s(.*)$/) {
				$irc->yield(privmsg => $nick => "Joining $1...");
				$irc->yield(join => $1);
			}
			if ($msg =~ /^\.part\s(.*)$/) {
				$irc->yield(privmsg => $nick => "Leaving $1...");
				$irc->yield(part => $1);
			}
			if ($msg =~ /^\.yield\s(.*)$/) {
				my @args = (split /\s/,$1);
				my $num = @args;
				$irc->yield(privmsg => $nick => "yield: @args ($num)");
				$irc->yield($args[0] => $args[1] => $args[2] => $args[3]);
			}
			if ($msg =~ /^\.wi\s(.*)$/) {
				$irc->yield(privmsg => $nick => "WHOIS $1");
				$irc->yield(whois => $1);
			}
			if ($msg =~ /^\.msg\s(.*)$/) {
				my @msg = (split /\s/,$1);
				my $r = shift(@msg);
				$irc->yield(privmsg => $r => "@msg");
			}
			if ($msg =~ /^\.nick\s(.*)$/) {
				my @m = (split /\s/,$1);
				$irc->yield(nick => $m[1]);
			}
			if ($msg =~ /^\.r\s(.*)$/) {
				my $m = rainbow($1,undef);
				$irc->yield(privmsg => $nick => $m);
			}
			if ($msg =~ /^\.c\s(\d+)\s(\d+)\s(.+)$/) {
				my $text = color($1,$2,$3);
				$irc->yield(privmsg => $nick => $text);
			}
			if ($msg =~ /^\.chans$/) {
				chanlist();
			}
			if ($msg =~ /^\.reload$/) {
				loadconfig();
			}
		}
	}
}

sub on_public {
  my ($kernel, $who, $where, $msg) = @_[KERNEL, ARG0, ARG1, ARG2];
  my $nick    = (split /!/, $who)[0];
  my $channel = $where->[0];
  my $ts      = scalar localtime;
  print "[$ts] <$nick:$channel> $msg\n";
  if ($msg =~ /((mailto\:|(news|(ht|f)tp(s?))\:\/\/){1}\S+)/) {
	my $uri = $1;
        if ($uri =~ /(youtube\.com)\/watch\?/) { #youtube
	  	youtube($uri,$channel);
	}
	elsif ($uri =~ /(youtu\.be)\/(.)+/) {
		youtube($uri,$channel);
	}
	else {
		titlan($uri,$channel,$nick);
	}

  }
  if ($msg =~ /^\s*same\s*$/) {
    same($1, $channel);
  }
 if ($msg =~ /^\.r\s(.*)$/) {
         my $m = rainbow($1,undef);
         $irc->yield(privmsg => $channel => $m);
 }
 if ($msg =~ /^\.w\s(.+)$/) {
	weather($1,$channel);
 }
 if ($msg =~ /^\.np\s+([a-zA-Z0-9]+)*/) {
    lastfm($1, $channel);
 }

  given($nick) {
	when (/^shelf$/) {
		if ($msg =~ /^\.k\s(.*)/) {
			say "Kicking $1 from $channel...";
			$irc->yield(kick => $channel => $1);
		}
	}
	when (/^seugwizi$/) {
	}
  }
}

sub on_notice {
	my ($kernel,$who,$where,$msg) = @_[KERNEL,ARG0,ARG1,ARG2];
	my $nick = (split /!/,$who)[0];
	my $channel = $where->[0];
	my $ts = scalar localtime;
	say "NOTICE: <$nick> $msg";
}

sub on_ctcp {
	my ($kernel,$ctcp,$who,$where,$msg) = @_[KERNEL,ARG0,ARG1,ARG2,ARG3];
	my $nick = (split /!/,$who)[0];
	my $channel = $where->[0];
	my $ts = scalar localtime;
	given($ctcp) {
		when(/^(v|V)((ersion)|(ERSION))/) {
			$irc->yield(ctcpreply => $nick => 'VERSION POEbot 0.1');
			say "CTCP reply to $nick: VERSION POEbot 0.1";
		}
		when(/^action/) {
			say "[$ts] <$nick:$channel> ** $msg";
		}
		default {
			say "CTCP: <$nick> $ctcp";
		}
	}
}

sub on_mode {
#my $args = @_[ARG0 .. $#_];
	my ($kernel,$who,$where,$mode) = @_[KERNEL,ARG0,ARG1,ARG2];
	my @victims = @_[ARG3 .. $#_];
	my $nick = (split /!/,$who)[0];
	my $ts = scalar localtime;
#	say "Victims: " . @victims;
#	say "@victims";
 	print "[$ts] $nick sets mode $mode";
	if (defined($victims[0])) { #mode changed on users, not channel
		print " on @victims";
		print " in $where.\n";
	}
	elsif ($where =~ /^saa$/) { #it looks funny when mode set on you
		print " on $where.\n"
	}
	else {
		print " in $where.\n";
	}
}

sub on_join {
	my ($who,$where) = @_[ARG0,ARG1];
	my $nick = (split /!/,$who)[0];
}

sub on_nick {
	my $ts = scalar localtime;
	my ($who,$new) = @_[ARG0,ARG1];
	my $nick = (split/!/,$who)[0];
	say "[$ts] $nick is now known as $new";
}

sub on_quit {
	my $ts = scalar localtime;
	my ($who,$where,$why) = @_[ARG0,ARG1,ARG2];
	if (!$why) { #quit
		say "[$ts] $who has quit [$where]";
	}
	else { #probably a part
		say "[$ts] $who has left #$where [$why]";
	}
}

sub on_kick {
	my ($kernel,$who,$channel,$victim,$reason) = @_[KERNEL,ARG0,ARG1,ARG2,ARG3];
	my $nick = (split /!/,$who)[0];
	my $ts = scalar localtime;
	say "[$ts] $nick has kicked $victim from $channel [$reason]";
	if ($victim =~/^saa$/) {
		sleep 5;
		$irc->yield(join => $channel);
	}
}

sub on_whois {
	my ($kernel,$hashan) = @_[KERNEL,ARG0];
	my @chans = @{$hashan->{'channels'}};
	my ($nick,$user,$host,$real,$server) = @{ $hashan }{ qw/nick user host real server/ };
	say "$nick!$user\@$host is $real";
	say "$nick is on $server";
	say "$nick is in @chans";
}

sub on_whois_ident {
	my @id = @{ $_[ARG2] };
	say "@id";
	
}

sub chanlist {
	my $chns = $irc->channels();
#	say Dumper($chns);
	return $chns;
}

sub titlan {
	my ($u,$ch,$n) = @_;
	my $chanref = $chanhash->{$ch};
	if ($chanref->{'uri'} != 0) {
		my $title = title($u);
		if (defined $title) {
			if (length($title) > 150) {
				my $diff = (length($title)) - 150;
				$title = substr($title,0,-($diff));
			}
			if ($title =~ /(ACTION|CTCP)/) {
				$irc->yield(kick => $ch => $n => "get out");
				return undef;
			}
			$title = "[URI] " . $title;
			$irc->yield(privmsg => $ch => $title);
		}
	}
	return undef;
}

sub youtube {
	my ($u,$ch) = @_;
	my $chanref = $chanhash->{$ch};
	if ($chanref->{'youtube'} != 0) {
		my $t = title($u);
		if (defined $t) {
			if ($t =~ /(.*)(\s-\sYouTube)$/) {
				my $you = color(1,0,"You");
				my $tube = color(0,5,"Tube");
				$t = $you . $tube . " " . $1;
			} 
			$irc->yield(privmsg => $ch => $t);
		}
		else {
			say "Title request failed for: $u";
		}
		return $t if (defined $t);
	}
	return undef;
}

sub weather {
	my ($w,$ch) = @_;
	my $chanref = $chanhash->{$ch};
	if ($chanref->{'weather'} != 0) {
		my $weather = new Weather::Google($w);
		my $info = $weather->forecast_information;
		my $city = $info->{city};
		my @info = $weather->current('temp_f','temp_c','humidity','wind_condition');
		my $ret = "Weather for $city: " . $info[0] . "F/" . $info[1] . "C. " . $info[2] . ". " . $info[3];
		$irc->yield(privmsg => $ch => $ret);
	}
	return undef;
}

sub lastfm {
    my ($u, $ch) = @_;
    my $chanref = $chanhash->{$ch};
    my $root = "http://ws.audioscrobbler.com/2.0/";
    if ($chanref->{'lastfm'} != 0) {
        my $key = $config->{'lastfmkey'};
        my $ret = "Sorry, this doesn't work yet.";
        $irc->yield(privmsg => $ch => $ret);
    }
    return undef;
}

sub same {
    my ($u, $ch) = @_;
    my $chanref = $chanhash->{$ch};
    my $msg = "same";
    $irc->yield(privmsg => $ch => $msg);
    return undef;
}

$poe_kernel->run();
exit 0;
