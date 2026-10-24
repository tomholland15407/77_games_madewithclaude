package com.gogs.bananagame.games

import com.gogs.bananagame.core.GameDefinition
import com.gogs.bananagame.games.jungleloop.JungleLoopGame
import com.gogs.bananagame.games.chefsorder.ChefsOrderGame
import com.gogs.bananagame.games.spotthedifference.SpotTheDifferenceGame
import com.gogs.bananagame.games.assassin.AssassinGame
import com.gogs.bananagame.games.parkking.ParkKingGame
import com.gogs.bananagame.games.lawndefense.LawnDefenseGame
import com.gogs.bananagame.games.critterduel.CritterDuelGame
import com.gogs.bananagame.games.planecrash.PlaneCrashGame
import com.gogs.bananagame.games.ledgebrawl.LedgeBrawlGame
import com.gogs.bananagame.games.colortide.ColorTideGame
import com.gogs.bananagame.games.quickdraw.QuickDrawGame
import com.gogs.bananagame.games.freethebanana.FreeTheBananaGame
import com.gogs.bananagame.games.airhockey.AirHockeyGame
import com.gogs.bananagame.games.lagoonislands.LagoonIslandsGame
import com.gogs.bananagame.games.berrybalance.BerryBalanceGame
import com.gogs.bananagame.games.grooveslider.GrooveSliderGame
import com.gogs.bananagame.games.lineconnect.LineConnectGame
import com.gogs.bananagame.games.toppleblock.ToppleBlockGame
import com.gogs.bananagame.games.bottleorder.BottleOrderGame
import com.gogs.bananagame.games.pearlchain.PearlChainGame
import com.gogs.bananagame.games.spiralgalaxies.SpiralGalaxiesGame
import com.gogs.bananagame.games.compounddash.CompoundDashGame
import com.gogs.bananagame.games.breach.BreachGame
import com.gogs.bananagame.games.nuggethook.NuggetHookGame
import com.gogs.bananagame.games.cupshuffle.CupShuffleGame
import com.gogs.bananagame.games.slide2048.Slide2048Game
import com.gogs.bananagame.games.turboracer.TurboRacerGame
import com.gogs.bananagame.games.statuemaze.StatueMazeGame
import com.gogs.bananagame.games.colortrap.ColorTrapGame
import com.gogs.bananagame.games.tankmaze.TankMazeGame
import com.gogs.bananagame.games.pegsolitaire.PegSolitaireGame
import com.gogs.bananagame.games.quickmath.QuickMathGame
import com.gogs.bananagame.games.memory.MemoryGame
import com.gogs.bananagame.games.headerduel.HeaderDuelGame
import com.gogs.bananagame.games.towerofhanoi.TowerOfHanoiGame
import com.gogs.bananagame.games.lightsout.LightsOutGame
import com.gogs.bananagame.games.mazemuncher.MazeMuncherGame
import com.gogs.bananagame.games.laserdodge.LaserDodgeGame
import com.gogs.bananagame.games.brickbreaker.BrickBreakerGame
import com.gogs.bananagame.games.dodgeball.DodgeballGame
import com.gogs.bananagame.games.chesssweep.ChessSweepGame
import com.gogs.bananagame.games.bananaflutter.BananaFlutterGame
import com.gogs.bananagame.games.stack.StackGame
import com.gogs.bananagame.games.juiceblade.JuiceBladeGame
import com.gogs.bananagame.games.sketchhop.SketchHopGame
import com.gogs.bananagame.games.jetpackbanana.JetpackBananaGame
import com.gogs.bananagame.games.squaresprint.SquareSprintGame
import com.gogs.bananagame.games.prismpass.PrismPassGame
import com.gogs.bananagame.games.logdarts.LogDartsGame
import com.gogs.bananagame.games.rainbowroll.RainbowRollGame

/** The master list of games shown in the feed, in the iOS `GameRegistry.all` order. */
object GameRegistry {
    val all: List<GameDefinition> by lazy {
        listOf(
            PegSolitaireGame.definition,
            QuickMathGame.definition,
            MemoryGame.definition,
            TankMazeGame.definition,
            ColorTrapGame.definition,
            StatueMazeGame.definition,
            TurboRacerGame.definition,
            Slide2048Game.definition,
            CupShuffleGame.definition,
            NuggetHookGame.definition,
            BreachGame.definition,
            CompoundDashGame.definition,
            SpiralGalaxiesGame.definition,
            PearlChainGame.definition,
            BottleOrderGame.definition,
            ToppleBlockGame.definition,
            LineConnectGame.definition,
            GrooveSliderGame.definition,
            BerryBalanceGame.definition,
            LagoonIslandsGame.definition,
            AirHockeyGame.definition,
            FreeTheBananaGame.definition,
            QuickDrawGame.definition,
            ColorTideGame.definition,
            LedgeBrawlGame.definition,
            PlaneCrashGame.definition,
            CritterDuelGame.definition,
            LawnDefenseGame.definition,
            JungleLoopGame.definition,
            ChefsOrderGame.definition,
            SpotTheDifferenceGame.definition,
            AssassinGame.definition,
            ParkKingGame.definition,
            HeaderDuelGame.definition,
            TowerOfHanoiGame.definition,
            LightsOutGame.definition,
            MazeMuncherGame.definition,
            LaserDodgeGame.definition,
            BrickBreakerGame.definition,
            DodgeballGame.definition,
            ChessSweepGame.definition,
            BananaFlutterGame.definition,
            StackGame.definition,
            JuiceBladeGame.definition,
            SketchHopGame.definition,
            JetpackBananaGame.definition,
            SquareSprintGame.definition,
            PrismPassGame.definition,
            LogDartsGame.definition,
            RainbowRollGame.definition,
        )
    }
}
