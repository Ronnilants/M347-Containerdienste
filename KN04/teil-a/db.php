<?php
$connection = mysqli_connect("m347-kn04a-db", "root", "rootpassword", "mysql");
if ($connection) {
    echo "<h1>Verbindung erfolgreich!</h1>";
} else {
    echo "<h1>Verbindung fehlgeschlagen: " . mysqli_connect_error() . "</h1>";
}
?>
