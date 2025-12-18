Message J3.2 Rules {
    TransmitRules {
        Rule "Rule 1: J3.2B Basic Message Transmission" {
            Condition: Text("by the JU with R²") AND (
                           OnEvent(SystemCue("When reporting a new air track on the interface"))
                           OR OnEvent(SystemCue("When assuming R² of an air track"))
                           OR OnEvent(SystemCue("When a track alert is initiated on the air track"))
                           OR (Timing is Periodic("RRN=6, 12s, 8-20s interval") AND Text("for real-time air tracks"))
                           OR (Timing is Periodic("RRN=4, 48s, 36-60s interval") AND Text("for non-real-time air tracks"))
                           OR (OnEvent(SystemCue("When identity changes")) AND Text("for real-time air tracks"))
                           OR (OnEvent(SystemCue("When any data element changes")) AND Text("for non-real-time air tracks"))
                           OR (OnEvent(ReceiptOf("J7.1")) AND Field(J7.1.Action) == 1)
                           OR (OnEvent(SystemCue("When J2.2 Air PPLI messages are no longer being received")) AND Text("for which local sensor data exist, in accordance with paragraph 4.4.2.2.1"))
                           OR (OnEvent(ReceiptOf("J7.5")) AND Field(J7.5.Action) == 2)
                           OR OnEvent(SystemCue("When any IFF/SIF data are changed from No Data status (zero) to Valid Data status (nonzero)"))
                       )
            Action:    "The J3.2B Air Track basic message (J3.2I and J3.2E0) shall be transmitted."
        }

     Rule "Rule 2: J3.2C1 Continuation Word Transmission" {
         Condition: Text("by the JU with R²") AND (
                        (Text("if any data elements in the J3.2C1 word are held for real-time air tracks") AND (
                            OnEvent(SystemCue("When reporting a new air track on the interface"))
                            OR OnEvent(SystemCue("When assuming R² of an air track"))
                            OR OnEvent(SystemCue("When a track alert is initiated on the air track"))
                            OR (OnEvent(ReceiptOf("J7.1")) AND Field(J7.1.Action) == 1)
                            OR OnEvent(SystemCue("When J2.2 Air PPLI messages are no longer being received"))
                        ))
                        OR (OnEvent(SystemCue("when any data in the J3.2C1 word changes")) AND Text("At the next periodic transmission of the basic message"))
                        OR (Text("Every 4th (1-8, 1) transmission of the J3.2B basic message") AND Text("for real-time air tracks"))
                        OR Text("for non-real-time air tracks")
                        OR (OnEvent(ReceiptOf("J7.5")) AND Field(J7.5.Action) == 2)
                        OR Text("When Air Platform and/or Air Platform Activity... may be sent in alternate transmissions with the Air Specific Type Indicator set to value 0 and then 1")
                    )
         Action:    "The J3.2C1 Air Track Amplification continuation word shall be transmitted."
     }

     Rule "Rule 3: J3.2C4 Continuation Word Transmission" {
         Condition: Text("by the JU with R²") AND (
                        (Text("if any data elements in the J3.2C4 word are held for real-time air tracks") AND (
                            OnEvent(SystemCue("When reporting a new air track on the interface"))
                            OR OnEvent(SystemCue("When assuming R² of an air track"))
                            OR OnEvent(SystemCue("When a track alert is initiated on the air track"))
                            OR (OnEvent(ReceiptOf("J7.1")) AND Field(J7.1.Action) == 1)
                            OR OnEvent(SystemCue("When J2.2 Air PPLI messages are no longer being received"))
                        ))
                        OR (OnEvent(SystemCue("when any data in the J3.2C4 word changes")) AND Text("At the next periodic transmission of the basic message"))
                        OR (Text("Every 8(1-16, 1) transmission of the J3.2B basic message for real-time air tracks") AND Text("if any data elements in the J3.2C4 word are held"))
                        OR Text("for non-real-time air tracks")
                    )
         Action:    "The J3.2C4 Air Track Amplification continuation word shall be transmitted."
     }
 
     Rule "Rule 4: Cease Transmission" {
         Condition: OnEvent(ReceiptOf("J2.2")) AND Text("from the unit being reported once the TN correlation has been accomplished")
         Action:    "The J3.2 messages on the specified air track shall cease being transmitted."
     }
}

}