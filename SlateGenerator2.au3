#AutoIt3Wrapper_Change2CUI=y

#include <FileConstants.au3>
#include <StringConstants.au3>
#include <Array.au3>
#include <File.au3>

Global $SourceFolder = $CmdLine[1] ;"./Results"
Global $OutputFolder = $CmdLine[2] ;@ScriptDir&"/source/index.html.md"

Global $Log = FileOpen(@ScriptDir & "\SlateGenerator2.log", 2)
Global $DataFile = FileOpen(@ScriptDir & "\TreeHierarchy.csv", 2)

#include "Parser.au3"
#include "DataStorer.au3"

Func ExitCleanly()
	FileWrite($Log, "SlateGenerator2 exited cleanly")
	FileClose($Log)
	FileClose($DataFile)
EndFunc

; Takes an array and returns it in a markdown flavored list
Func ArrayToList($Array)
	$String = ""
	For $i = 0 To UBound($Array) - 3 Step 3
		$String &= "* "
		$String &= $Array[$i] & " "
		$String &= $Array[$i + 1]
		If $Array[$i + 2] <> "" And $Array[$i + 2] <> " " And $Array[$i + 2] <> 0  Then
			$String &= " : " & $Array[$i + 2] & @CRLF
		Else
			$String &= @CRLF
		EndIf
	Next
	Return $String
EndFunc

Func IdentifyBlock($Block, $Declaration)
	Local $Kind
	Local $KindFunction

	$Kind = ParseForOneTag($Block, "@module")
	If $Kind Then
		Return "module"
	EndIf

	$Kind = ParseForOneTag($Block, "@type")
	If $Kind Then
		Return "type"
	EndIf


	$KindFunction = ParseFunctionName($Block, $Declaration)
	If $KindFunction[0] Then
		Return "function"
	EndIf

	Return ""
EndFunc


Func WriteModule($Block, $Group)
	Local $ModuleName = ParseForOneTag($Block, "@module")
	DirCreate(@ScriptDir & "\TEMP")
	Local $Output = FileOpen(@ScriptDir & "\TEMP\" & $Group & "." & $ModuleName & ".md", $FO_OVERWRITE)
	Local $Data = ""
	Local $DataPos = 1
	Local $Return[2]

	; Add title of Module
	FileWrite($Output, "# " & $Group & "." & $ModuleName & " Module" & @CRLF)

	; Copy the short description
	While StringRight($Data, 1) <> @CRLF And StringRight($Data, 1) <> @CR
		If StringRight($Data, 7) == "@module" Then ; If there is no comment in the module block
			$Return[0] = $Output
			$Return[1] = $ModuleName
			Return $Return
		EndIf
		$Data &= StringMid($Block, $DataPos, 1)
		$DataPos += 1
	WEnd
	$Data = StringTrimRight($Data, 1)
	$Block = StringTrimLeft($Block, $DataPos)
	FileWrite($Output, $Data & @CRLF)

	; copy the long description
	$DataPos = 1
	$Data = ""
	$Omit = False
	While StringRight($Data, 7) <> "@module"
		$Data &= StringMid($Block, $DataPos, 1)
		$DataPos += 1
	WEnd
	$Data = StringTrimRight($Data, 8)
	FileWrite($Output, $Data & @CRLF)
	$Return[0] = $Output
	$Return[1] = $ModuleName
	Return $Return
EndFunc

Func WriteType($Block, $ModuleName, $Output)
	Local $TypeName = ParseForOneTag($Block, "@type")
	Local $ParentClass = GetData($TypeName, "parent")
	Local $Fields = ParseForTags($Block, "@field")

	; Add title of Type
	FileWrite($Output, "## " & $TypeName & " Class" & @CRLF)

	; Add hierearchy info if necessary. Some cool ASCII drawing is going on !
	If $ParentClass <> "ROOT" Then
		FileWrite($Output, "**Inheritance : The " & $TypeName & " class inherits from the following parents**" & @CRLF)
		Local $Hierarchy = GetParents($TypeName)
		Local $String = ""
		Local $TabBuffer = @TAB
		For $i=0 to UBound($Hierarchy)-1
			$String &= $TabBuffer&"`-- "&$ParentClass[$i]&@CRLF
			$TabBuffer &= @TAB
		Next
		FileWrite($Output, $String)
	Else
		FileWrite($Output, "**The " & $TypeName & " class does not inherit**" & @CRLF)
	EndIf

	; Copy the long description
	Local $DataPos = 1
	Local $Data = ""
	Local $Omit = False

	While StringRight($Data, 1) <> @CR ; We discard the first line
		$Data &= StringMid($Block, $DataPos, 1)
		$DataPos += 1
	WEnd
	; If there is a tag in the first line, there is no description
	if StringInStr($Data, "@type") == 0 and StringInStr($Data, "@extends") == 0 and StringInStr($Data, "@field") == 0 Then
		$Data = ""
		$DataPos += 1

		While StringRight($Data, 5) <> "@type"
			$Data &= StringMid($Block, $DataPos, 1)
			$DataPos += 1
		WEnd
		$Data = StringTrimRight($Data, 5)
		FileWrite($Output, $Data & @CRLF)
	EndIf

	; Add the Attributes
	If $Fields <> "" Then
		FileWrite($Output, "#### Attributes" & @CRLF & @CRLF)
		FileWrite($Output, ArrayToList($Fields) & @CRLF)
	EndIf
	Return $TypeName
EndFunc


; Main

Local $SourceList = _FileListToArrayRec($SourceFolder, "*", $FLTAR_FILES, $FLTAR_RECUR, $FLTAR_NOSORT, $FLTAR_FULLPATH)
Local $CurrentFile
Local $CarretPos = 0
Local $CommentBlock
Local $CommentKind
Local $CommentInfo[2]

Local $CurrentModule


ConsoleWrite("1. Parsing Source Files... ")
FileWrite($Log, @CRLF&@CRLF&@TAB&"INFO : Building Hierarchy" & @CRLF)
For $i=1 To $SourceList[0]
	$CurrentFile = FileOpen($SourceList[$i], $FO_READ)
	FileWrite($Log, @CRLF&"INFO : Reading File "&$SourceList[$i] & @CRLF)
	While True
		$CommentBlock = ReadNextBlock($CurrentFile, $CarretPos)
		If Not $CommentBlock[1] Then
			ExitLoop
		EndIf

		$CarretPos = $CommentBlock[0]
		$CommentKind = IdentifyBlock($CommentBlock[1], $CommentBlock[2])
		Switch $CommentKind
			Case "function"
				$CommentInfo = ParseFunctionName($CommentBlock[1], $CommentBlock[2])
				AddNode("function", $CurrentModule, $CommentInfo[0], $CommentInfo[1], $SourceList[$i], $CommentBlock[3])
				FileWrite($Log, "INFO : Added function "&$CommentInfo[0]&" to hierarchy" & @CRLF)
			Case "type"
				$CommentInfo[0] = ParseForOneTag($CommentBlock[1], "@type")
				$CommentInfo[1] = ParseForOneTag($CommentBlock[1], "@extends")
				$CommentInfo[1] = StringRegExpReplace($CommentInfo[1], "(.*#)", "")
				AddNode("type", $CurrentModule, $CommentInfo[0], $CommentInfo[1], $SourceList[$i], $CommentBlock[3])
				FileWrite($Log, "INFO : Added type "&$CommentInfo[0]&" to hierarchy" & @CRLF)
			Case "module"
				$CurrentModule = ParseForOneTag($CommentBlock[1], "@module")
				AddNode("module", "", $CurrentModule, "", $SourceList[$i], $CommentBlock[3])
				FileWrite($Log, "INFO : Added type "&$CurrentModule&" to hierarchy" & @CRLF)
		EndSwitch

	WEnd
	$CarretPos = 0
	FileClose($CurrentFile)
Next
ConsoleWrite("Done"&@CRLF)

ConsoleWrite("2. Sorting Hierarchy")
FileWrite($Log, @CRLF&@CRLF&@TAB&"INFO : Sorting Hierarchy" & @CRLF)
DataSort()
ConsoleWrite("Done"&@CRLF)

#cs
Local $CurrentFolder
Local $CurrentModule
Local $CurrentOutput
Local $RegexResult
Local $Return[2]
ConsoleWrite("2. Writing Markdown Documentation"&@CRLF)
FileWrite($Log, @CRLF&@CRLF&@TAB&"INFO : Writing Markdown Documentation" & @CRLF)
For $i=1 To $SourceList[0]
	$CurrentFile = FileOpen($SourceList[$i], $FO_READ)
	$RegexResult = StringRegExp($SourceList[$i], ".*\\(.*)\\.*\.lua", $STR_REGEXPARRAYMATCH)
	If @error Then
		$CurrentFolder = "."
	Else
		$CurrentFolder = $RegexResult[0]
	EndIf
	While True
		$CommentBlock = ReadNextBlock($CurrentFile, $CarretPos)
		If Not $CommentBlock[1] Then
			ExitLoop
		EndIf

		$CarretPos = $CommentBlock[0]
		$CommentKind = IdentifyBlock($CommentBlock[1], $CommentBlock[2])
		Switch $CommentKind
			Case "module"
				FileWrite($Log, "INFO : Module Found ! "& @CRLF)
				$Return = WriteModule($CommentBlock[1], $CurrentFolder)
				$CurrentOutput = $Return[0]
				$CurrentModule = $Return[1]
				ConsoleWrite(@TAB&"Created File "&$CurrentFolder&"."&$CurrentModule&@CRLF)
				FileWrite($Log, "INFO : Markdown written for Module " &$CurrentModule& @CRLF)
			Case "type"
				FileWrite($Log, "INFO : Type Found ! "& @CRLF)
				WriteType($CommentBlock[1], $ModuleName, $Output)
		EndSwitch
	Wend
	$CarretPos = 0
	FileClose($CurrentFile)
Next
#ce

ExitCleanly()