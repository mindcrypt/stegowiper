# stegokick

Over the past 10 years, many threat groups have employed stegomalware or other steganography-based techniques to attack organizations in all industries and regions of the world. Examples include TA551-IcedID, RainDrop, Plantium APT, Ursnif, Powload, Oceanlotus APT-32, Waterbug/Turla, Lokibot, TheDukes, NanoCore RAT, Bebloh*, Oilrig*, MT3, ObliqueRAT, SteamHIde, LightNeuron/Turla, etc.

Our research shows that most groups are employing very simple techniques (at least from an academic perspective) and tools known only to circumvent perimeter defenses, although more advanced groups are also using steganography techniques to hide C&C communication and data exfiltration. This lack of sophistication is not due to a lack of knowledge of steganography (some APTs have already experimented with more advanced algorithms) but simply because organizations are not able to defend against even the most basic steganography techniques.

For this reason, we created stegoKick to blindly disrupt any image-based stegomalware (the most), attacking the weakest point of all steganography algorithms (robustness). We show that it is capable of disrupting all currently employed steganography techniques, as well as the most advanced algorithms available in the academic literature. In fact, the more sophisticated a technique is, the more disruption our tool provides.

Our active attack allows us to disrupt the most famous steganographic tool (f5, Steghide, openstego, ...) even the most sophisticated algorithm based on matrix encryption, wet-papers, etc. (Hill, Hugo, etc.)

# Usage & Parameters

```
examples
```

# Examples - Breaking steganography

```
examples
```

# Future work. Doing
- We are working to support the ICAP protocol. Stegokick using ICAP could connect to other systems to block stegomalware in real traffic.


# Author & license

This project has been developed by Dr. Alfonso Muñoz and Dr. Manuel Urueña The code is released under the GNU General Public License v3.
