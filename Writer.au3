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

Func WriteModule($Block, $Group)
	Local $ModuleName = ParseForOneTag($Block, "@module")
	DirCreate(@ScriptDir & "\TEMP")
	Local $Output = FileOpen(@ScriptDir & "\TEMP\" & $Group & "." & $ModuleName & ".md", $FO_OVERWRITE)
	Local $Data = ""
	Local $DataPos = 1

	ConsoleWrite("Writing "&$Group & "." & $ModuleName & ".md" &@CRLF)
	FileWrite($Log, @CRLF&@TAB&"Writing "&$Group & "." & $ModuleName & ".md" &@CRLF)
	FileWrite($Log, "Writing Module "&$ModuleName&@CRLF)

	; Add title of Module
	FileWrite($Output, "# " & $Group & "." & $ModuleName & " Module" & @CRLF)

	; Copy the short description
	While StringRight($Data, 1) <> @CRLF And StringRight($Data, 1) <> @CR
		If StringRight($Data, 7) == "@module" Then ; If there is no comment in the module block
			Return $Output
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
	Return $Output
EndFunc


Func WriteType($Block, $ModuleName, $Output)
	Local $TypeName = ParseForOneTag($Block, "@type")
	Local $ParentClass = GetData($TypeName, "parent")
	Local $Fields = ParseForTags($Block, "@field")

	FileWrite($Log, "Writing Type "&$TypeName&@CRLF)

	; Add title of Type
	FileWrite($Output, "## " & $TypeName & " Class" & @CRLF)

	; Add hierearchy info if necessary. Some cool ASCII drawing is going on !
	If $ParentClass <> "ROOT" Then
		FileWrite($Output, "**Inheritance : The " & $TypeName & " class inherits from the following parents**" & @CRLF)
		Local $Hierarchy = GetParents($TypeName)
		Local $String = ""
		Local $TabBuffer = @TAB
		For $i=0 to UBound($Hierarchy)-1
			$String &= $TabBuffer&"`-- "&$Hierarchy[$i]&@CRLF
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

