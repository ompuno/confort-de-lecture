#!/usr/bin/perl

#########################################################################
# BEGIN COPYRIGHT, LICENSE AND WARRANTY NOTICE
# SOFTWARE NAME: Confort de lecture
# SOFTWARE RELEASE: 2.0.0
# COPYRIGHT NOTICE: Copyright (C) 2000-2007 GIE Confort de lecture (aYaline & HandicapZéro)
# SOFTWARE LICENSE: GNU General Public License v3
# NOTICE:
# This file is part of Confort de lecture.
#
# Confort de lecture is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
#
# Confort de lecture is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with Confort de lecture. If not, see <http://www.gnu.org/licenses/>.
#########################################################################

# File: exit_from_cdl.pl
#	Script de porte de sortie de CDL vers un site qui n'est pas géré par CDL

use CGI::Carp qw(fatalsToBrowser);

use CGI qw(:standard);
use CGI::Session;

use Cwd;

if (-e "./JSON") {
	use lib 'JSON';
}
use JSON;
use Encode;

use HTML::Entities;

use Digest::SHA::PurePerl qw(sha1_hex);

use lib '../modules/utils';
use constants;
use misc_utils;
use session;
use config_manager;

use lib '../modules/html';
use misc_html;


# Récupération de l'id du site courant
my $siteId = param('cdlid');

# Création de l'objet CGI
my $cgi = CGI->new();

# Création de la session et récupération de l'objet de gestion de la session
my $session = createOrGetSession($cgi);

print $session->header('Content-type' => "text/html; charset=UTF-8");

# Récupération de l'URL réécrite pour en extraire les informations nécessaires
my $thisCdlUrl = $ENV{'REQUEST_URI'};
$thisCdlUrl =~ s/%20/+/sgi;

$embeddedMode = "";

# Extraction des différents paramètres dans l'URL réécrite
my ($secure, $defaultLanguage, $requestMethod, $urlToParse);
$thisCdlUrl =~ s/^((\/cdl)?\/sortie(\-http(s))?\/([^\/]*)\/([^\/]*)\/([^\/]*)\/([^\?]*))/
	$embeddedMode = $2;
	$secure = $4;
	$siteId = $5;
	$defaultLanguage = $6;
	$requestMethod = $7;
	$urlToParse = $8;
	$1/segi;

if (!$siteId and $embeddedMode ne "") {
	my $siteDomain = $ENV{'SERVER_NAME'};
	$siteId = getSiteFromDomain($siteDomain);
}

# Détection d'erreurs au niveau de l'identifiant du site
if (!$siteId) {
	die "Aucun identifiant de site n'a été renseigné.\n";
	exit;
}
if (!existConfigDirectory($siteId)) {
	die "Aucun site ne correspond à l'identifiant : ".$siteId.".\n";
	exit;
}

# Inclusion du module extension général à tous les sites
require($cdlSitesConfigPath."default_override.pm");

# Inclusion du module extension spécifique au site s'il y en a un
if (-e $cdlSitesConfigPath.$siteId."/override/main.pm") {
	require($cdlSitesConfigPath.$siteId."/override/main.pm");
}

my $defaultConfiguration = loadConfig($cdlSitesConfigPath."default.ini");
my $siteConfiguration = loadConfig($cdlSitesConfigPath.$siteId."/".$siteId.".ini");
my $enableAudio = getConfig($siteConfiguration, 'enableAudio');
if ($enableAudio eq "") {
	$enableAudio = getConfig($defaultConfiguration, 'enableAudio');
}

# Chargement de la template principale de la page de sortie vers un site externe
my $exitPageTemplateString = loadConfig($cdlTemplatesPath."exit_from_cdl.html");

$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'EMBEDDED_URL', $embeddedMode);

# La langue du site
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'SITE_ID', $siteId);

# La langue du site
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'LANGUAGE', $defaultLanguage);

# Génération de la table des hachage des paramètres
my @paramKeys = param;
my %requestParameters;
foreach my $paramKey (@paramKeys) {
	my @paramValuesArray = param($paramKey);
	$requestParameters{$paramKey} = \@paramValuesArray;
}

my $hiddenPostParameters = '';
if ($requestMethod =~ m/post/si) {
	my $postRequestParametersString = loadFromSession($session, 'cdl_post_parameters_to_exit');
	if ($postRequestParametersString) {
		my %postRequestParameters = %{decode_json($postRequestParametersString)};

		foreach my $postRequestParameterName (keys(%postRequestParameters)) {
			my $refPostRequestParameterValues = $postRequestParameters{$postRequestParameterName};
			my @postRequestParameterValues = @$refPostRequestParameterValues;
			foreach my $postRequestParameterValue (@postRequestParameterValues) {
				$postRequestParameterValue =~ s/\r?\n/\\n/sgi;
				$postRequestParameterValue =~ s/\"/&quot;/sgi;
				$hiddenPostParameters .= '<input type="hidden" name="'.$postRequestParameterName.'" value="'.encode("utf8", $postRequestParameterValue).'">';
			}
		}
	}
	deleteFromSession($session, 'cdl_post_parameters_to_exit');
}

# L'URL externe vers laquelle on sort
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'REQUEST_METHOD', lc($requestMethod));
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'HIDDEN_POST_PARAMS', $hiddenPostParameters);
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'EXTERNAL_URL', "http".$secure."://".urlDecode(putParametersInUrl($urlToParse, %requestParameters)));

# L'URL de la page précédente pour annuler et retourner
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'PREVIOUS_PAGE', $ENV{'HTTP_REFERER'});

# Gestion du cache :
# Sauvegarder du contenu de la page dans un fichier temporaire
my $pageContentFile = savePageContentInCache($requestMethod, putParametersInUrl($urlToParse, %requestParameters), $exitPageTemplateString, loadFromSession($session, 'positionLocation')."_".loadFromSession($session, 'activateJavascript')."_".loadFromSession($session, 'activateFrames')."_".loadFromSession($session, 'displayImages')."_".loadFromSession($session, 'displayObjects')."_".loadFromSession($session, 'displayApplets')."_".loadFromSession($session, 'parseTablesToList'));

# Mettre le nom de ce fichier temporaire en parametre du lien vers le script de génération en audio
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'CONTENT_TO_READ_WITH_ACAPELA', $pageContentFile);

my $activateAudio = "";
if ($enableAudio) {
	# Récupération de la session de la variable indiquant si l'audio est activé
	$activateAudio = loadFromSession($session, 'activateAudio');
}

my $fontSize = loadFromSession($session, 'fontSize');
$fontSize = $fontSize ? $fontSize : 3;

if ($activateAudio eq "1") {
	$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'JS_AUDIO_FILE_INCLUDE', getPartOfTemplateString($exitPageTemplateString, 'JS_AUDIO_FILE_INCLUDE'));
	$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'AUDIO', getPartOfTemplateString($exitPageTemplateString, 'AUDIO'));
	$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'MP3_PLAYER_WIDTH', 200+3.85*(($fontSize - 1)*20));
	$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'MP3_PLAYER_HEIGHT', 50+0.7*(($fontSize - 1)*20));
	$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'DIV_MP3_PLAYER_HEIGHT', 40+0.7*(($fontSize - 1)*20));
	# Mettre le nom de domaine pour complèter les URLs absolues
	$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'AUDIO_SERVER_NAME', ($ttsMode eq "sdk" and $embeddedMode ne "" ? "solution.confortdelecture.org" :  $ENV{'SERVER_NAME'}.$embeddedMode));
} else {
	$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'JS_AUDIO_FILE_INCLUDE', "");
	$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'AUDIO', "");
}


my $backgroundColor = loadFromSession($session, 'backgroundColor');
my $fontColor = loadFromSession($session, 'fontColor');
my $linkColor = loadFromSession($session, 'linkColor');
$backgroundColor = $backgroundColor ? $backgroundColor : '000000';
$fontColor = $fontColor ? $fontColor : 'FFFFFF';
$linkColor = $linkColor ? $linkColor : $fontColor;
my $letterSpacing = loadFromSession($session, 'letterSpacing');
my $wordSpacing = loadFromSession($session, 'wordSpacing');
my $lineHeight = loadFromSession($session, 'lineHeight');
$letterSpacing = $letterSpacing ? $letterSpacing : '1';
$wordSpacing = $wordSpacing ? $wordSpacing : '1';
$lineHeight = $lineHeight ? $lineHeight : '1';

$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'B_COLOR', $backgroundColor);
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'F_COLOR', $fontColor);
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'L_COLOR', $linkColor);
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'F_SIZE', $fontSize);
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'L_SPACING', $letterSpacing);
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'W_SPACING', $wordSpacing);
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'L_HEIGHT', $lineHeight);
if (isBigCursorNotAllowed()) {
	$fontSize = 1;
}
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'FONT_SIZE_BROWSER_DEPENDS', $fontSize);

my @now = localtime(time);
$exitPageTemplateString = setValueInTemplateString($exitPageTemplateString, 'CURRENT_YEAR', 1900 + $now[5]);

print $exitPageTemplateString;