// Pins
#define RESISTOR_NEGATIVE 0  // A-Star 32u4 ADC pinout does not
#define RESISTOR_POSITIVE 1  // match what's printed on the board
#define MOSFET_GATE 12
#define INTERVAL 1000

// Variables
unsigned long time;
char output[11];
char input;

void setup()
{
  pinMode(RESISTOR_NEGATIVE, INPUT);
  pinMode(RESISTOR_POSITIVE, INPUT);
  pinMode(MOSFET_GATE, OUTPUT);
  pinMode(13, OUTPUT);
  Serial.begin(9600);
  time = millis();
  // Indicate setup is done
  digitalWrite(13, HIGH);
}

void loop()
{
  if (Serial.available() > 0)
  {
    input = Serial.read();
    if (input == '+') digitalWrite(MOSFET_GATE, HIGH);
    if (input == '-') digitalWrite(MOSFET_GATE, LOW);
  }

  if (millis() >= (time + INTERVAL))
  {
    time = millis();
    // Workaround for sprintf bug, every other variable ignored.
    // To solve this we overwrite the characters from output+5 with
    // the second part of the string.
    sprintf(output, "N%04u", analogRead(RESISTOR_NEGATIVE));
    sprintf(output+5, "P%04u", analogRead(RESISTOR_POSITIVE));
    Serial.println(output);
  }
}

